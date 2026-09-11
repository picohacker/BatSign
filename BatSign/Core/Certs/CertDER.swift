//
//  CertDER.swift
//  BatSign
//
//  Minimal X.509 DER walker used to extract subject CN/O and validity dates
//  from a certificate. (SecCertificateCopyValues and the kSecOID* property
//  keys are macOS-only; this works everywhere with zero dependencies.)
//

import Foundation

enum CertDER {
    struct Facts {
        var commonName: String?
        var organization: String?
        var notBefore: Date?
        var notAfter: Date?
    }

    enum Parse {
        static func tag(_ byte: UInt8) -> UInt8 { byte & 0x1F }
    }

    /// Decodes one TLV at `offset`. Returns content range and next offset.
    private static func tlv(_ bytes: [UInt8], _ offset: Int) -> (tag: UInt8, start: Int, length: Int, next: Int)? {
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]
        var cursor = offset + 1
        var length = 0
        let first = bytes[cursor]
        cursor += 1
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0 && count <= 4, cursor + count <= bytes.count else { return nil }
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[cursor])
                cursor += 1
            }
        }
        guard cursor + length <= bytes.count else { return nil }
        return (tag, cursor, length, cursor + length)
    }

    private static func children(_ bytes: [UInt8], _ start: Int, _ length: Int) -> [(start: Int, length: Int, tag: UInt8)] {
        var result: [(start: Int, length: Int, tag: UInt8)] = []
        var cursor = start
        let end = start + length
        while cursor < end {
            guard let node = tlv(bytes, cursor) else { break }
            result.append((node.start, node.length, node.tag))
            cursor = node.next
        }
        return result
    }

    // MARK: Public API

    static func facts(from certificateData: Data) -> Facts {
        var facts = Facts()
        let bytes = [UInt8](certificateData)

        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
        guard let outer = tlv(bytes, 0), outer.tag == 0x30 else { return facts }
        guard let tbsList = children(bytes, outer.start, outer.length).first,
              tbsList.tag == 0x30 else { return facts }

        // tbsCertificate ::= [0] version?, serial, sigAlg, issuer, validity, subject, ...
        let nodes = children(bytes, tbsList.start, tbsList.length)
        // Walk with explicit structure: skip [0] version if present.
        var index = 0
        if nodes.first?.tag == 0xA0 { index = 1 }
        guard nodes.count >= index + 4 else { return facts }
        let validity: (start: Int, length: Int, tag: UInt8)? = nodes[index + 3]
        let subject: (start: Int, length: Int, tag: UInt8)? = nodes.count > index + 4 ? nodes[index + 4] : nil

        if let validity {
            let times = children(bytes, validity.start, validity.length)
            if times.count >= 2 {
                facts.notBefore = parseTime(bytes, times[0])
                facts.notAfter = parseTime(bytes, times[1])
            }
        }

        if let subject {
            let (cn, org) = parseName(bytes, subject.start, subject.length)
            facts.commonName = cn
            facts.organization = org
        }
        return facts
    }

    /// Name ::= RDNSequence: SETs of SEQUENCE { OID, value }
    private static func parseName(_ bytes: [UInt8], _ start: Int, _ length: Int) -> (cn: String?, org: String?) {
        var cn: String?
        var org: String?
        for rdn in children(bytes, start, length) where rdn.tag == 0x31 {
            for attribute in children(bytes, rdn.start, rdn.length) where attribute.tag == 0x30 {
                let parts = children(bytes, attribute.start, attribute.length)
                guard parts.count >= 2, parts[0].tag == 0x06 else { continue }
                let oid = Array(bytes[parts[0].start..<(parts[0].start + parts[0].length)])
                let value = readString(bytes, parts[1])
                // 2.5.4.3 = CN, 2.5.4.10 = O
                if oid == [0x55, 0x04, 0x03] { cn = value ?? cn }
                if oid == [0x55, 0x04, 0x0A] { org = value ?? org }
            }
        }
        return (cn, org)
    }

    private static func readString(_ bytes: [UInt8], _ node: (start: Int, length: Int, tag: UInt8)) -> String? {
        let slice = Array(bytes[node.start..<(node.start + node.length)])
        switch node.tag {
        case 0x0C, 0x13, 0x16: // UTF8String, PrintableString, IA5String
            return String(bytes: slice, encoding: .utf8) ?? String(bytes: slice, encoding: .isoLatin1)
        case 0x1E: // BMPString (UTF-16BE)
            let data = Data(slice)
            return String(data: data, encoding: .utf16BigEndian)
        default:
            return nil
        }
    }

    private static func parseTime(_ bytes: [UInt8], _ node: (start: Int, length: Int, tag: UInt8)) -> Date? {
        let raw = String(bytes: bytes[node.start..<(node.start + node.length)], encoding: .ascii) ?? ""
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if node.tag == 0x17 { // UTCTime YYMMDDHHMMSSZ
            formatter.dateFormat = "yyMMddHHmmss'Z'"
        } else if node.tag == 0x18 { // GeneralizedTime YYYYMMDDHHMMSSZ
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        } else {
            return nil
        }
        return formatter.date(from: raw)
    }
}
