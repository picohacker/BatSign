//
//  DebUnpacker.swift
//  BatSign
//
//  Unpacks Debian tweak packages (.deb) entirely in-process:
//  ar archive → data.tar.{gz,zst,tar} → tar → .dylib payloads.
//  xz-compressed debs are rejected with an honest error (no liblzma).
//

import Foundation
import Compression

enum DebUnpackError: LocalizedError {
    case notADeb
    case noDataTar
    case unsupportedCompression(String)
    case corrupt(String)
    case tooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .notADeb: return "This is not a .deb package (missing ar archive header)."
        case .noDataTar: return "No data.tar found inside this .deb."
        case .unsupportedCompression(let what): return "This .deb uses \(what) compression, which BatSign can't unpack. Repack it with gzip or zstd."
        case .corrupt(let why): return "Corrupt package: \(why)"
        case .tooLarge(let mb): return "Package is too large (\(mb) MB)."
        }
    }
}

enum DebUnpacker {
    static let maxPackageBytes: Int64 = 500 * 1024 * 1024

    /// Extracts every .dylib in the package into `destination`.
    /// Returns the file names written.
    static func extractDylibs(from url: URL, into destination: URL) throws -> [String] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? Int64) ?? 0
        guard size <= maxPackageBytes else {
            throw DebUnpackError.tooLarge(size / (1024 * 1024))
        }

        let bytes = [UInt8](try Data(contentsOf: url))

        // --- ar archive walk ------------------------------------------------
        guard bytes.count > 8, String(bytes: bytes[0..<8], encoding: .ascii) == "!<arch>\n" else {
            throw DebUnpackError.notADeb
        }
        var cursor = 8
        var gnuNameTable: [UInt8]?
        var dataTarMember: [UInt8]?
        var dataTarName: String?

        while cursor + 60 <= bytes.count {
            let nameField = String(bytes: bytes[cursor..<(cursor + 16)], encoding: .ascii) ?? ""
            let sizeField = String(bytes: bytes[(cursor + 48)..<(cursor + 58)], encoding: .ascii) ?? ""
            let magic = String(bytes: bytes[(cursor + 58)..<(cursor + 60)], encoding: .ascii) ?? ""
            guard magic == "`\n" else { throw DebUnpackError.corrupt("bad ar member header") }

            let memberSize = Int(sizeField.trimmingCharacters(in: .whitespaces)) ?? 0
            var name = nameField.trimmingCharacters(in: .whitespaces)
            var dataStart = cursor + 60
            var dataLength = memberSize

            if name == "//" { // GNU long-name table
                gnuNameTable = Array(bytes[dataStart..<(dataStart + memberSize)])
            } else if name.hasPrefix("#1/") { // BSD extended name
                let nameLength = Int(name.dropFirst(3)) ?? 0
                if nameLength > 0 && nameLength < memberSize,
                   let real = String(bytes: bytes[dataStart..<(dataStart + nameLength)], encoding: .utf8) {
                    name = real.trimmingCharacters(in: CharacterSet(arrayLiteral: "\0"))
                }
                dataStart += nameLength
                dataLength = memberSize - nameLength
            } else if name.hasSuffix("/") { // GNU short name
                name.removeLast()
            }

            if name.hasPrefix("data.tar") {
                dataTarMember = Array(bytes[dataStart..<(dataStart + dataLength)])
                dataTarName = name
                break
            }
            cursor = dataStart + dataLength
            if cursor % 2 == 1 { cursor += 1 } // ar pads members to even offsets
        }

        guard var tarBytes = dataTarMember, let memberName = dataTarName else {
            throw DebUnpackError.noDataTar
        }

        // --- decompress -----------------------------------------------------
        if memberName.hasSuffix(".tar.xz") || memberName.hasSuffix(".tar.lzma") {
            throw DebUnpackError.unsupportedCompression("xz")
        } else if memberName.hasSuffix(".tar.zst") {
            tarBytes = try zstdDecompress(tarBytes)
        } else if memberName.hasSuffix(".tar.gz") || memberName.hasSuffix(".tar.tgz") {
            tarBytes = try gzipDecompress(tarBytes)
        } else if !memberName.hasSuffix(".tar") {
            throw DebUnpackError.corrupt("unknown data member '\(memberName)'")
        }

        // --- tar walk -------------------------------------------------------
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var written: [String] = []
        var offset = 0
        var pendingLongName: String?

        while offset + 512 <= tarBytes.count {
            let block = Array(tarBytes[offset..<(offset + 512)])
            if block.allSatisfy({ $0 == 0 }) { break }
            offset += 512

            // Header fields are space/NUL-padded ASCII.
            let fieldCharset = CharacterSet(charactersIn: " \0")
            var name = String(bytes: block[0..<100], encoding: .utf8)?
                .trimmingCharacters(in: fieldCharset) ?? ""
            let sizeOctal = String(bytes: block[124..<136], encoding: .ascii)?
                .trimmingCharacters(in: fieldCharset) ?? "0"
            let size = Int(sizeOctal, radix: 8) ?? 0
            let typeFlag = block[156]
            let prefix = String(bytes: block[345..<500], encoding: .utf8)?
                .trimmingCharacters(in: fieldCharset) ?? ""
            if !prefix.isEmpty { name = "\(prefix)/\(name)" }
            if let longName = pendingLongName {
                name = longName
                pendingLongName = nil
            }

            let paddedSize = ((size + 511) / 512) * 512
            let contentStart = offset
            offset += paddedSize

            switch typeFlag {
            case UInt8(ascii: "L"): // GNU long name — next block holds it
                if contentStart + size <= tarBytes.count {
                    pendingLongName = String(bytes: tarBytes[contentStart..<(contentStart + size)], encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(arrayLiteral: "\0"))
                }
            case UInt8(ascii: "0"), 0: // regular file
                guard contentStart + size <= tarBytes.count else {
                    throw DebUnpackError.corrupt("tar entry '\(name)' out of bounds")
                }
                // Skip AppleDouble resource forks and macOS junk that ride
                // along in debs built on a Mac — they are not real dylibs.
                let fileName = (name as NSString).lastPathComponent
                guard name.hasSuffix(".dylib"), !fileName.hasPrefix("._") else { continue }
                let outURL = destination.appendingPathComponent(fileName)
                try Data(tarBytes[contentStart..<(contentStart + size)]).write(to: outURL, options: [.atomic])
                written.append(fileName)
            default:
                continue
            }
        }

        if written.isEmpty {
            // The package is valid but carries no dylibs — tell the user honestly.
        }
        return written
    }

    // MARK: gzip

    private static func gzipDecompress(_ input: [UInt8]) throws -> [UInt8] {
        guard input.count > 18, input[0] == 0x1F, input[1] == 0x8B, input[2] == 8 else {
            throw DebUnpackError.corrupt("not a gzip stream")
        }
        let flags = input[3]
        var cursor = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard cursor + 2 <= input.count else { throw DebUnpackError.corrupt("truncated gzip extra") }
            let extraLen = Int(input[cursor]) | (Int(input[cursor + 1]) << 8)
            cursor += 2 + extraLen
        }
        if flags & 0x08 != 0 { // FNAME
            while cursor < input.count && input[cursor] != 0 { cursor += 1 }
            cursor += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while cursor < input.count && input[cursor] != 0 { cursor += 1 }
            cursor += 1
        }
        if flags & 0x02 != 0 { cursor += 2 } // FHCRC
        guard cursor + 9 <= input.count else { throw DebUnpackError.corrupt("truncated gzip header") }

        let deflated = Array(input[cursor..<(input.count - 8)]) // strip CRC32+ISize footer
        let maxOut = 256 * 1024 * 1024
        var output = [UInt8](repeating: 0, count: maxOut)
        let written = deflated.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                compression_decode_buffer(outBuf.baseAddress!, maxOut,
                                          inBuf.baseAddress!, deflated.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < maxOut else { throw DebUnpackError.corrupt("gzip inflate failed or exceeded 256 MB") }
        return Array(output[0..<written])
    }

    // MARK: zstd (libzstd, linked) — streaming, handles frames without a
    // declared content size (dpkg-deb streams its tar through zstd).

    private static func zstdDecompress(_ input: [UInt8]) throws -> [UInt8] {
        guard let ctx = ZSTD_createDCtx() else {
            throw DebUnpackError.corrupt("zstd: context allocation failed")
        }
        defer { _ = ZSTD_freeDCtx(ctx) }

        let chunk = 1 << 20
        let cap = 512 * 1024 * 1024
        let dst = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 64)
        defer { dst.deallocate() }

        var output = [UInt8]()
        output.reserveCapacity(1 << 20)

        // The input pointer must stay valid for the whole streaming loop,
        // so the loop lives inside the buffer-pinning closure.
        try input.withUnsafeBufferPointer { inBuf in
            var inBuffer = ZSTD_inBuffer(src: inBuf.baseAddress, size: inBuf.count, pos: 0)
            while true {
                var outBuffer = ZSTD_outBuffer(dst: dst, size: chunk, pos: 0)
                let ret = ZSTD_decompressStream(ctx, &outBuffer, &inBuffer)
                if ZSTD_isError(ret) != 0 {
                    throw DebUnpackError.corrupt("zstd: \(String(cString: ZSTD_getErrorName(ret)))")
                }
                output.append(contentsOf: UnsafeRawBufferPointer(start: dst, count: outBuffer.pos))
                if output.count > cap {
                    throw DebUnpackError.tooLarge(Int64(output.count / (1024 * 1024)))
                }
                if ret == 0 { break } // frame fully decoded
                if inBuffer.pos == inBuf.count && outBuffer.pos == 0 {
                    throw DebUnpackError.corrupt("zstd: stream ended mid-frame")
                }
            }
        }
        guard !output.isEmpty else { throw DebUnpackError.corrupt("zstd: empty output") }
        return output
    }
}
