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

private let LEAF_B64 = "MIIDCjCCAfKgAwIBAgIJANUhvftXy82tMA0GCSqGSIb3DQEBCwUAMCwxEzARBgNVBAoMCkJhdFRlc3QgQ0ExFTATBgNVBAMMDEJhdFRlc3QgUm9vdDAeFw0yNjA5MTEyMDAzMzlaFw0yNjEwMTEyMDAzMzlaMCwxFDASBgNVBAoMC0JhdFRlc3QgT3JnMRQwEgYDVQQDDAtCYXRUZXN0IERldjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAODh9rYGDso52BtUtWavI/Y0DfYL12SrEcmmJISUN4f8qxf676nO87hhrUgI23fxP8WluIndnbu/+shGbTpa1RAO0nINRsOhcuOXNReuAX6zG4H02x9U2cHtoztlX+jVAr1Xnl6QRm0Vop3QjHZTTsQ6tmebV5Q/8prA/HFW/SpK2wCiYk+maFvdmxW1Ny0ilIvijVXO+mepa2ADPK8Hc1DQfHU5xDlG4RvfnuKByDCDR449R8mKGAC88GSeG2t95aO70P9WWVTRHmik0W8sYKihpM1FOVA+4vbIXKGfI4DK1iorcZ78eOEUB3PmVlioVEf4a/9yJRiZQIqe2KLujEECAwEAAaMvMC0wCQYDVR0TBAIwADALBgNVHQ8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwDQYJKoZIhvcNAQELBQADggEBAFzBh6SYeisJwAo3CHIhb4ysetApSKWxfVYu+ih+cOoXqp5L/vXwSiQ4ySHJlRnN12xdR8ujbJZAKuuGlJ5+16yk02BvPVSSJd1He8mLCUsci8cKXxRoD/TkWnTjSSKWlnnCisBxiNdoNKQQIFGTBZUESIT58WSv4HqGB/hxNC4BdLTnuTfHaH/Fj+tiDE81QZkBGXq2SGBQKEFRic15q6cOoAvxUJCNHeE3bjgWysu1wWHEO7/Qf+51SbfsAoKoxlQasA4ayuYro6/Q0LvWxJfUbB1WUT3DiGr1i1KHRR1aGeI2shG+ZnAbNeeoGCGQ1oeqN07rzc1No5MuPpVHM1E="
