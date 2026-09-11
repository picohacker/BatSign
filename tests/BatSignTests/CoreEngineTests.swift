//
//  CoreEngineTests.swift
//  BatSignTests
//
//  Real automated coverage for the zero-dependency core: ZIP reader,
//  deb unpacker, provisioning-profile parser, and the X.509 DER walker.
//

import XCTest
@testable import BatSign

final class ZipReaderTests: XCTestCase {
    func testReadsStoredEntriesAndSizes() throws {
        let payload = Data("hello plist payload".utf8)
        let blob = Data(repeating: 0xAB, count: 4096)
        let zip = TestArchives.zip(entries: [
            ("Payload/App.app/Info.plist", payload),
            ("Payload/App.app/icon.png", blob),
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).zip")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try ZipReader(url: url)
        XCTAssertEqual(reader.entries.count, 2)

        let info = try XCTUnwrap(reader.entry(named: "Payload/App.app/Info.plist"))
        XCTAssertEqual(try reader.readData(info), payload)

        let icon = try XCTUnwrap(reader.entry(named: "Payload/App.app/icon.png"))
        XCTAssertEqual(icon.uncompressedSize, 4096)
        XCTAssertEqual(try reader.readData(icon), blob)
    }

    func testEntryLookupMissReturnsNil() throws {
        let zip = TestArchives.zip(entries: [("a.txt", Data("x".utf8))])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).zip")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try ZipReader(url: url)
        XCTAssertNil(reader.entry(named: "missing.txt"))
        XCTAssertNil(reader.firstEntry(matching: { $0.name.hasSuffix(".plist") }))
    }
}

final class DebUnpackerTests: XCTestCase {
    private func makeDeb(compressed: Data, suffix: String) -> Data {
        let tar = TestArchives.tar(entries: [
            ("./Library/MobileSubstrate/DynamicLibraries/testtweak.dylib", Data(repeating: 0x7F, count: 256)),
        ])
        let gz = TestArchives.gzip(tar)
        _ = compressed
        _ = suffix
        return TestArchives.ar(members: [
            ("debian-binary", Data("2.0\n".utf8)),
            ("control.tar.gz", TestArchives.gzip(Data("Package: x\n".utf8))),
            ("data.tar.gz", gz),
        ])
    }

    func testExtractsDylibFromGzipDeb() throws {
        let deb = makeDeb(compressed: Data(), suffix: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).deb")
        try deb.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("out-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let names = try DebUnpacker.extractDylibs(from: url, into: out)
        XCTAssertEqual(names, ["testtweak.dylib"])
        let data = try Data(contentsOf: out.appendingPathComponent("testtweak.dylib"))
        XCTAssertEqual(data.count, 256)
    }

    func testRejectsNonDeb() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).deb")
        try Data("definitely not an ar archive".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try DebUnpacker.extractDylibs(
            from: url,
            into: FileManager.default.temporaryDirectory.appendingPathComponent("out-\(UUID().uuidString)")))
    }
}

final class ProfileParserTests: XCTestCase {
    func testParsesDevelopmentProfileFacts() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Name</key><string>BatTest Profile</string>
        <key>TeamName</key><string>BatTest Team</string>
        <key>TeamIdentifier</key><array><string>BATTEAM01</string></array>
        <key>ExpirationDate</key><date>2027-01-01T00:00:00Z</date>
        <key>ProvisionedDevices</key><array><string>abc123</string><string>def456</string></array>
        <key>Entitlements</key><dict>
        <key>application-identifier</key><string>BATTEAM01.com.example.app</string>
        <key>get-task-allow</key><true/>
        </dict></dict></plist>
        """
        let profile = try ProfileParser.parse(data: Data(plist.utf8))
        XCTAssertEqual(profile.name, "BatTest Profile")
        XCTAssertEqual(profile.teamName, "BatTest Team")
        XCTAssertEqual(profile.teamIDs, ["BATTEAM01"])
        XCTAssertEqual(profile.provisionedDevices.count, 2)
        XCTAssertEqual(profile.applicationIDPrefix, "BATTEAM01")
        XCTAssertEqual(profile.applicationIDBundle, "com.example.app")
        XCTAssertTrue(profile.getTaskAllow)
        XCTAssertEqual(profile.kind, .development)
        XCTAssertNotNil(profile.expiration)
        XCTAssertNotNil(ProfileParser.entitlementsXML(profile.entitlements))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ProfileParser.parse(data: Data("garbage".utf8)))
    }
}

final class CertDERTests: XCTestCase {
    func testExtractsSubjectAndValidityFromRealCertificate() throws {
        let base64 = "\(LEAF_B64)"
        let der = try XCTUnwrap(Data(base64Encoded: base64))
        let facts = CertDER.facts(from: der)
        XCTAssertEqual(facts.commonName, "BatTest Dev")
        XCTAssertEqual(facts.organization, "BatTest Org")
        XCTAssertNotNil(facts.notBefore)
        XCTAssertNotNil(facts.notAfter)
        let lifetime = try XCTUnwrap(facts.notAfter?.timeIntervalSince(facts.notBefore ?? Date()))
        XCTAssertGreaterThan(lifetime, 0)
    }

    func testGarbageReturnsEmptyFacts() {
        let facts = CertDER.facts(from: Data("junk".utf8))
        XCTAssertNil(facts.commonName)
        XCTAssertNil(facts.notAfter)
    }
}

private let LEAF_B64 = """
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURDakNDQWZLZ0F3SUJBZ0lKQU5VaHZmdFh5ODJ0TUEwR0NTcUdTSWIzRFFFQkN3VUFNQ3d4RXpBUkJnTlYKQkFvTUNrSmhkRlJsYzNRZ1EwRXhGVEFUQmdOVkJBTU1ERUpoZEZSbGMzUWdVbTl2ZERBZUZ3MHlOakE1TVRFeQpNREF6TXpsYUZ3MHlOakV3TVRFeU1EQXpNemxhTUN3eEZEQVNCZ05WQkFvTUMwSmhkRlJsYzNRZ1QzSm5NUlF3CkVnWURWUVFEREF0Q1lYUlVaWE4wSUVSbGRqQ0NBU0l3RFFZSktvWklodmNOQVFFQkJRQURnZ0VQQURDQ0FRb0MKZ2dFQkFPRGg5cllHRHNvNTJCdFV0V2F2SS9ZMERmWUwxMlNyRWNtbUpJU1VONGY4cXhmNjc2bk84N2hoclVnSQoyM2Z4UDhXbHVJbmRuYnUvK3NoR2JUcGExUkFPMG5JTlJzT2hjdU9YTlJldUFYNnpHNEgwMng5VTJjSHRvenRsClgralZBcjFYbmw2UVJtMFZvcDNRakhaVFRzUTZ0bWViVjVRLzhwckEvSEZXL1NwSzJ3Q2lZayttYUZ2ZG14VzEKTnkwaWxJdmlqVlhPK21lcGEyQURQSzhIYzFEUWZIVTV4RGxHNFJ2Zm51S0J5RENEUjQ0OVI4bUtHQUM4OEdTZQpHMnQ5NWFPNzBQOVdXVlRSSG1pazBXOHNZS2locE0xRk9WQSs0dmJJWEtHZkk0REsxaW9yY1o3OGVPRVVCM1BtClZsaW9WRWY0YS85eUpSaVpRSXFlMktMdWpFRUNBd0VBQWFNdk1DMHdDUVlEVlIwVEJBSXdBREFMQmdOVkhROEUKQkFNQ0I0QXdFd1lEVlIwbEJBd3dDZ1lJS3dZQkJRVUhBd013RFFZSktvWklodmNOQVFFTEJRQURnZ0VCQUZ6QgpoNlNZZWlzSndBbzNDSEloYjR5c2V0QXBTS1d4ZlZZdStpaCtjT29YcXA1TC92WHdTaVE0eVNISmxSbk4xMnhkClI4dWpiSlpBS3V1R2xKNSsxNnlrMDJCdlBWU1NKZDFIZThtTENVc2NpOGNLWHhSb0QvVGtXblRqU1NLV2xubkMKaXNCeGlOZG9OS1FRSUZHVEJaVUVTSVQ1OFdTdjRIcUdCL2h4TkM0QmRMVG51VGZIYUgvRmordGlERTgxUVprQgpHWHEyU0dCUUtFRlJpYzE1cTZjT29BdnhVSkNOSGVFM2JqZ1d5c3Uxd1dIRU83L1FmKzUxU2Jmc0FvS294bFFhCnNBNGF5dVlybzYvUTBMdld4SmZVYkIxV1VUM0RpR3IxaTFLSFJSMWFHZUkyc2hHK1puQWJOZWVvR0NHUTFvZXEKTjA3cnpjMU5vNU11UHBWSE0xRT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
"""
