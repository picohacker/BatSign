//
//  ZipReader.swift
//  BatSign
//
//  Minimal, dependency-free ZIP reader used for IPA introspection
//  (Info.plist, icons, Mach-O probing). Supports stored + deflate entries,
//  ZIP64 records, and data descriptors. The signing engine handles the
//  heavy full-archive work itself.
//

import Foundation
import Compression

struct ZipEntry: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let method: UInt16
    let localHeaderOffset: UInt64

    var id: String { name }
}

enum ZipError: LocalizedError {
    case notAZipFile
    case corrupt(String)
    case unsupported(String)
    case entryTooLarge(UInt64)

    var errorDescription: String? {
        switch self {
        case .notAZipFile: return "The file is not a zip archive."
        case .corrupt(let why): return "Corrupt zip archive: \(why)"
        case .unsupported(let why): return "Unsupported zip feature: \(why)"
        case .entryTooLarge(let size): return "Entry too large to read into memory (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."
        }
    }
}

final class ZipReader {
    static let maxInMemoryEntry: UInt64 = 512 * 1024 * 1024

    private let file: FileHandle
    private(set) var entries: [ZipEntry] = []
    private(set) var centralDirectoryCount = 0

    deinit {
        try? file.close()
    }

    init(url: URL) throws {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw ZipError.corrupt("cannot open file")
        }
        file = handle
        try parseCentralDirectory()
    }

    // MARK: Directory parsing

    private func parseCentralDirectory() throws {
        let totalSize = try file.seekToEnd()
        let scanWindow: UInt64 = min(totalSize, 66_000)
        try file.seek(toOffset: totalSize - scanWindow)
        let tail = try file.read(upToCount: Int(scanWindow)) ?? Data()

        guard let eocdRange = tail.range(of: Data([0x50, 0x4B, 0x05, 0x06]),
                                         options: [.backwards]) else {
            throw ZipError.notAZipFile
        }
        let eocd = eocdRange.lowerBound
        guard tail.count - eocd >= 22 else { throw ZipError.corrupt("truncated EOCD") }

        var entryCount = Int(readU16(tail, eocd + 10))
        var cdSize = UInt64(readU32(tail, eocd + 12))
        var cdOffset = UInt64(readU32(tail, eocd + 16))

        // ZIP64: locate the locator directly before the EOCD.
        if cdOffset == 0xFFFF_FFFF || entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF {
            let locatorEnd = eocd
            guard locatorEnd >= 20 else { throw ZipError.unsupported("zip64 locator out of range") }
            let locatorStart = locatorEnd - 20
            let locatorSig = readU32(tail, locatorStart)
            if locatorSig == 0x0706_4B50 {
                let zip64EOCDOffset = readU64(tail, locatorStart + 8)
                try file.seek(toOffset: zip64EOCDOffset)
                guard let eocd64 = try file.read(upToCount: 56), eocd64.count >= 56,
                      readU32(eocd64, 0) == 0x0606_4B50 else {
                    throw ZipError.corrupt("bad zip64 EOCD")
                }
                entryCount = Int(readU64(eocd64, 32))
                cdSize = readU64(eocd64, 40)
                cdOffset = readU64(eocd64, 48)
            } else {
                throw ZipError.unsupported("zip64 marker missing")
            }
        }

        centralDirectoryCount = entryCount
        try file.seek(toOffset: cdOffset)
        guard let cdData = try file.read(upToCount: Int(min(cdSize, 1_000_000_000))),
              cdData.count == Int(cdSize) else {
            throw ZipError.corrupt("central directory unreadable")
        }

        var cursor = 0
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard cursor + 46 <= cdData.count, readU32(cdData, cursor) == 0x0201_4B50 else {
                throw ZipError.corrupt("bad central directory entry")
            }
            let flags = readU16(cdData, cursor + 8)
            let method = readU16(cdData, cursor + 10)
            var compressedSize = UInt64(readU32(cdData, cursor + 20))
            var uncompressedSize = UInt64(readU32(cdData, cursor + 24))
            let nameLength = Int(readU16(cdData, cursor + 28))
            let extraLength = Int(readU16(cdData, cursor + 30))
            let commentLength = Int(readU16(cdData, cursor + 32))
            var localOffset = UInt64(readU32(cdData, cursor + 42))

            guard cursor + 46 + nameLength <= cdData.count else {
                throw ZipError.corrupt("entry name out of bounds")
            }
            let nameData = cdData.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? String(data: nameData, encoding: .nonLossyASCII)
                ?? ""

            // ZIP64 extra field (id 0x0001) — sizes and offset appear only when truncated.
            var extraCursor = cursor + 46 + nameLength
            let extraEnd = extraCursor + extraLength
            if flags & 0x08 != 0 { /* data descriptor: central sizes are authoritative */ }
            while extraCursor + 4 <= extraEnd {
                let fieldID = readU16(cdData, extraCursor)
                let fieldSize = Int(readU16(cdData, extraCursor + 2))
                let fieldDataStart = extraCursor + 4
                if fieldID == 0x0001, fieldDataStart + fieldSize <= extraEnd {
                    var p = fieldDataStart
                    if uncompressedSize == 0xFFFF_FFFF, p + 8 <= extraEnd {
                        uncompressedSize = readU64(cdData, p); p += 8
                    }
                    if compressedSize == 0xFFFF_FFFF, p + 8 <= extraEnd {
                        compressedSize = readU64(cdData, p); p += 8
                    }
                    if localOffset == 0xFFFF_FFFF, p + 8 <= extraEnd {
                        localOffset = readU64(cdData, p); p += 8
                    }
                }
                extraCursor = fieldDataStart + fieldSize
            }

            let isDirectory = name.hasSuffix("/")
            entries.append(ZipEntry(name: name,
                                    isDirectory: isDirectory,
                                    compressedSize: compressedSize,
                                    uncompressedSize: uncompressedSize,
                                    method: method,
                                    localHeaderOffset: localOffset))
            cursor = extraEnd + commentLength
        }
    }

    // MARK: Reading

    func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    func firstEntry(matching predicate: (ZipEntry) -> Bool) -> ZipEntry? {
        entries.first(where: predicate)
    }

    func entries(matching predicate: (ZipEntry) -> Bool) -> [ZipEntry] {
        entries.filter(predicate)
    }

    /// Reads and (if needed) inflates one entry into memory.
    func readData(_ entry: ZipEntry) throws -> Data {
        guard !entry.isDirectory else { return Data() }
        guard entry.uncompressedSize <= Self.maxInMemoryEntry else {
            throw ZipError.entryTooLarge(entry.uncompressedSize)
        }
        guard entry.method == 0 || entry.method == 8 else {
            throw ZipError.unsupported("compression method \(entry.method)")
        }
        if entry.method == 0 && entry.compressedSize != entry.uncompressedSize {
            throw ZipError.corrupt("stored size mismatch")
        }

        try file.seek(toOffset: entry.localHeaderOffset)
        guard let local = try file.read(upToCount: 30), local.count == 30,
              readU32(local, 0) == 0x0403_4B50 else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        if readU16(local, 6) & 0x1 != 0 {
            throw ZipError.unsupported("encrypted entry \(entry.name)")
        }
        let localNameLen = Int(readU16(local, 26))
        let localExtraLen = Int(readU16(local, 28))
        let dataStart = entry.localHeaderOffset + 30 + UInt64(localNameLen + localExtraLen)

        try file.seek(toOffset: dataStart)
        guard let raw = try file.read(upToCount: Int(entry.compressedSize)),
              raw.count == Int(entry.compressedSize) else {
            throw ZipError.corrupt("entry data truncated: \(entry.name)")
        }

        if entry.method == 0 {
            return raw
        }
        return try inflate(raw, expectedSize: entry.uncompressedSize)
    }

    private func inflate(_ input: Data, expectedSize: UInt64) throws -> Data {
        var output = Data(count: Int(expectedSize))
        let result = output.withUnsafeMutableBytes { outBuf in
            input.withUnsafeBytes { inBuf -> Int in
                guard let inBase = inBuf.baseAddress, let outBase = outBuf.baseAddress else { return -1 }
                return compression_decode_buffer(
                    outBase.assumingMemoryBound(to: UInt8.self), Int(expectedSize),
                    inBase.assumingMemoryBound(to: UInt8.self), input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard result == Int(expectedSize) else {
            throw ZipError.corrupt("inflate produced \(result) of \(expectedSize) bytes")
        }
        return output
    }

    // MARK: Primitive readers (little-endian)

    private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | (UInt16(data[i + 1]) << 8)
    }

    private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
    }

    private func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(readU32(data, offset)) | (UInt64(readU32(data, offset + 4)) << 32)
    }
}
