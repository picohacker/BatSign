//
//  TestArchives.swift
//  BatSignTests
//
//  Minimal in-test builders: store-only ZIP writer, tar writer, gzip writer,
//  ar writer. These let ZipReader/DebUnpacker be tested without fixtures.
//

import Foundation
import Compression

enum TestArchives {
    // MARK: ZIP (store method only — ZipReader supports stored + deflate)

    static func zip(entries: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0

        func le16(_ v: UInt16) -> Data {
            withUnsafeBytes(of: v.littleEndian) { Data($0) }
        }
        func le32(_ v: UInt32) -> Data {
            withUnsafeBytes(of: v.littleEndian) { Data($0) }
        }

        for (name, data) in entries {
            let nameBytes = Data(name.utf8)
            let offset = UInt32(out.count)
            let crc = crc32(data)

            out += le32(0x0403_4B50)          // local header sig
            out += le16(20)                    // version needed
            out += le16(0)                     // flags
            out += le16(0)                     // method: stored
            out += le16(0) + le16(0)           // time, date
            out += le32(crc)
            out += le32(UInt32(data.count))
            out += le32(UInt32(data.count))
            out += le16(UInt16(nameBytes.count))
            out += le16(0)                     // extra len
            out += nameBytes
            out += data

            central += le32(0x0201_4B50)
            central += le16(20) + le16(20)
            central += le16(0) + le16(0)
            central += le16(0) + le16(0)
            central += le32(crc)
            central += le32(UInt32(data.count))
            central += le32(UInt32(data.count))
            central += le16(UInt16(nameBytes.count))
            central += le16(0) + le16(0) + le16(0)   // extra, comment, disk start
            central += le16(0)                       // internal attrs
            central += le32(0)                       // external attrs
            central += le32(offset)
            central += nameBytes
            count += 1
        }

        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50)
        out += le16(0) + le16(0)
        out += le16(count) + le16(count)
        out += le32(UInt32(central.count))
        out += le32(cdOffset)
        out += le16(0)
        return out
    }

    // MARK: tar (ustar regular files)

    static func tar(entries: [(String, Data)]) -> Data {
        var out = Data()

        func octal(_ value: Int, length: Int) -> Data {
            var str = String(value, radix: 8)
            while str.count < length - 1 { str = "0" + str }
            return Data(str.utf8) + Data([0])
        }

        func header(name: String, size: Int) {
            var h = Data(name.utf8)
            h.append(contentsOf: [UInt8](repeating: 0, count: 100 - h.count))
            h += octal(0o644, length: 8)
            h += octal(0, length: 8)
            h += octal(0, length: 8)
            h += octal(size, length: 12)
            h += octal(0, length: 12)
            h += Data([0x20, 0x20, 0x20, 0x20, 0x20, 0x20]) // checksum field (spaces)
            h += Data([0x20, 0x00])
            h += Data([UInt8(ascii: "0")])
            h.append(contentsOf: [UInt8](repeating: 0x20, count: 100)) // magic+version+uname...
            h.append(contentsOf: [UInt8](repeating: 0, count: 512 - h.count))
            let sum = h.reduce(0) { $0 + Int($1) }
            let checksum = octal(sum, length: 7) + Data([0])
            h.replaceSubrange(148..<156, with: checksum)
            out += h
        }

        for (name, data) in entries {
            header(name: name, size: data.count)
            out += data
            let pad = (512 - data.count % 512) % 512
            out.append(contentsOf: [UInt8](repeating: 0, count: pad))
        }
        out.append(contentsOf: [UInt8](repeating: 0, count: 1024))
        return out
    }

    // MARK: gzip (header + raw deflate + CRC32/ISize footer)

    static func gzip(_ data: Data) -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0, 0x03])
        let deflated = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data in
            let cap = data.count + 1024
            let dst = UnsafeMutableRawPointer.allocate(byteCount: cap, alignment: 64)
            defer { dst.deallocate() }
            let n = compression_encode_buffer(dst.assumingMemoryBound(to: UInt8.self), cap,
                                              raw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                              nil, COMPRESSION_ZLIB)
            return Data(bytes: dst, count: n)
        }
        out += deflated
        out += withUnsafeBytes(of: crc32(data).littleEndian) { Data($0) }
        out += withUnsafeBytes(of: UInt32(truncatingIfNeeded: data.count).littleEndian) { Data($0) }
        return out
    }

    // MARK: ar

    static func ar(members: [(String, Data)]) -> Data {
        var out = Data("!<arch>\n".utf8)
        for (name, data) in members {
            var header = Data(name.utf8)
            header.append(contentsOf: [UInt8](repeating: 0x20, count: 16 - header.count)) // name
            header += Data("0".utf8)                                     // mtime "0"
            header.append(contentsOf: [UInt8](repeating: 0x20, count: 11))
            header += Data("0".utf8)                                     // uid
            header.append(contentsOf: [UInt8](repeating: 0x20, count: 5))
            header += Data("0".utf8)                                     // gid
            header.append(contentsOf: [UInt8](repeating: 0x20, count: 5))
            header += Data("100644".utf8)                                // mode
            header.append(contentsOf: [UInt8](repeating: 0x20, count: 2))
            var sizeStr = String(data.count)
            while sizeStr.count < 10 { sizeStr = " " + sizeStr }
            header += Data(sizeStr.utf8)
            header += Data([0x60, 0x0A])                                 // "`\n"
            precondition(header.count == 60, "ar header must be 60 bytes, got \(header.count)")
            out += header + data
            if data.count % 2 == 1 { out.append(0x0A) }
        }
        return out
    }

    // MARK: primitives

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
