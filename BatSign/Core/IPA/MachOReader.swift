//
//  MachOInfo.swift
//  BatSign
//
//  Reads the header of a Mach-O file (raw or thin arm64/armv7/x86_64 slice)
//  far enough to describe it: file type, architecture, and, for dylibs, the
//  install name. Pure Swift — used by the source viewer's dylib preview.
//

import Foundation

struct MachOInfo {
    enum FileType: String {
        case executable = "Executable"
        case dylib = "Dynamic Library"
        case bundle = "Bundle"
        case staticLib = "Static Archive"
        case fat = "Universal (fat) binary"
        case unknown = "Unknown"
    }

    var fileType: FileType
    var architecture: String
    var installName: String?
}

enum MachOReader {
    static func info(from data: Data) -> MachOInfo? {
        let bytes = [UInt8](data.prefix(4096))
        guard bytes.count >= 32 else { return nil }

        func u32(_ offset: Int) -> UInt32 {
            guard offset + 4 <= bytes.count else { return 0 }
            return UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        let magic = u32(0)

        // Fat container: report and stop (iOS app payloads are thin).
        if magic == 0xBEBA_FECA || magic == 0xCAFEBABE {
            return MachOInfo(fileType: .fat, architecture: "multiple slices", installName: nil)
        }
        guard magic == 0xFEED_FACF || magic == 0xFEED_FACE else { return nil }
        let is64 = magic == 0xFEED_FACF

        let cputype = u32(4)
        let fileTypeValue = u32(12)
        let ncmds = Int(u32(16))
        guard ncmds > 0, ncmds < 8192 else { return nil }

        let architecture: String
        switch cputype {
        case 0x0100_000C: architecture = "arm64"
        case 0x0000_000C: architecture = "armv7"
        case 0x0100_0007: architecture = "x86_64"
        case 0x0000_0007: architecture = "i386"
        default: architecture = String(format: "cputype 0x%08X", cputype)
        }

        let type: MachOInfo.FileType
        switch fileTypeValue {
        case 0x2: type = .executable
        case 0x6: type = .dylib
        case 0x8: type = .bundle
        default: type = .unknown
        }

        // Walk load commands for LC_ID_DYLIB (0xD) when this is a dylib.
        var installName: String?
        if type == .dylib {
            var offset = is64 ? 32 : 28
            for _ in 0..<ncmds {
                guard offset + 8 <= bytes.count else { break }
                let cmd = u32(offset)
                let cmdSize = Int(u32(offset + 4))
                guard cmdSize >= 8, offset + cmdSize <= bytes.count else { break }
                if cmd == 0x0000_000D { // LC_ID_DYLIB
                    // dylib_command layout: cmd(0), cmdsize(4),
                    // dylib.name.offset(8) — offset relative to command start.
                    let nameOffset = Int(u32(offset + 8))
                    let nameStart = offset + nameOffset
                    if nameOffset >= 24, nameStart < offset + cmdSize {
                        var nameBytes: [UInt8] = []
                        var p = nameStart
                        while p < min(offset + cmdSize, bytes.count), bytes[p] != 0 {
                            nameBytes.append(bytes[p])
                            p += 1
                            if nameBytes.count > 512 { break }
                        }
                        installName = String(bytes: nameBytes, encoding: .utf8)
                    }
                    break
                }
                offset += cmdSize
            }
        }

        return MachOInfo(fileType: type, architecture: architecture, installName: installName)
    }
}
