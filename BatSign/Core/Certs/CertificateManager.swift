//
//  CertificateManager.swift
//  BatSign
//
//  Certificate + provisioning profile storage and inspection.
//  p12 parsing uses the public SecPKCS12Import API.
//

import Foundation
import Security

enum CertKind: String, Codable {
    case development
    case distribution
    case enterprise
    case unknown

    var label: String {
        switch self {
        case .development: return "Development"
        case .distribution: return "App Store"
        case .enterprise: return "Enterprise"
        case .unknown: return "Unknown"
        }
    }
}

struct CertificateRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var commonName: String
    var organization: String
    var kind: CertKind
    var teamName: String
    var teamID: String
    var certNotBefore: Date?
    var certNotAfter: Date?
    var profileName: String
    var profileExpiration: Date?
    var profileCreated: Date?
    var deviceCount: Int
    var bundleIDPattern: String
    var addedAt: Date

    var p12URL: URL { Paths.certs.appendingPathComponent(id.uuidString).appendingPathComponent("cert.p12") }
    var profileURL: URL { Paths.certs.appendingPathComponent(id.uuidString).appendingPathComponent("profile.mobileprovision") }

    /// The date that actually gates installation: profiles expire before certs.
    var effectiveExpiration: Date? {
        switch (profileExpiration, certNotAfter) {
        case let (profile?, cert?): return min(profile, cert)
        case let (profile?, nil): return profile
        case let (nil, cert?): return cert
        default: return nil
        }
    }

    var isExpired: Bool {
        if let expiry = effectiveExpiration {
            return expiry < Date()
        }
        return false
    }

    var daysRemaining: Int? {
        guard let expiry = effectiveExpiration else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: expiry)).day
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CertificateRecord, rhs: CertificateRecord) -> Bool { lhs.id == rhs.id }
}

enum CertificateError: LocalizedError, Equatable {
    case wrongPassword
    case invalidP12
    case invalidProfile
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "Wrong password for this .p12 certificate."
        case .invalidP12: return "This file is not a valid .p12 identity."
        case .invalidProfile: return "This is not a valid provisioning profile."
        case .readFailed(let why): return "Could not read files: \(why)"
        }
    }
}

// Main-thread API: SwiftUI drives every call site.
final class CertificateManager: ObservableObject {
    /// Single shared instance — the app, engine queue and background keeper
    /// must all observe the same certificate store.
    static let shared = CertificateManager()

    @Published private(set) var certificates: [CertificateRecord] = []

    init() {
        load()
    }

    func load() {
        certificates = JSONStore.load([CertificateRecord].self, from: Paths.certsIndex) ?? []
        certificates.sort { ($0.effectiveExpiration ?? .distantFuture) < ($1.effectiveExpiration ?? .distantFuture) }
    }

    private func persist() {
        JSONStore.save(certificates, to: Paths.certsIndex)
    }

    func certificate(with id: UUID) -> CertificateRecord? {
        certificates.first { $0.id == id }
    }

    func password(for record: CertificateRecord) -> String? {
        KeychainStore.get(for: record.id.uuidString)
    }

    func entitlements(for record: CertificateRecord) -> [String: Any] {
        guard let data = try? Data(contentsOf: record.profileURL),
              let profile = try? ProfileParser.parse(data: data) else { return [:] }
        return profile.entitlements
    }

    func devices(for record: CertificateRecord) -> [String] {
        guard let data = try? Data(contentsOf: record.profileURL),
              let profile = try? ProfileParser.parse(data: data) else { return [] }
        return profile.provisionedDevices
    }

    func profileData(for record: CertificateRecord) -> Data? {
        try? Data(contentsOf: record.profileURL)
    }

    // MARK: Import

    func importCertificate(p12URL: URL, profileURL: URL, password: String) throws -> CertificateRecord {
        guard let p12Data = FileManager.default.contents(atPath: p12URL.path) else {
            throw CertificateError.readFailed("p12 unreadable")
        }
        guard let profileRaw = FileManager.default.contents(atPath: profileURL.path) else {
            throw CertificateError.readFailed("profile unreadable")
        }

        let (commonName, organization, notBefore, notAfter) = try inspectP12(p12Data, password: password)
        let profile = try ProfileParser.parse(data: profileRaw)

        let id = UUID()
        let dir = Paths.certs.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try p12Data.write(to: dir.appendingPathComponent("cert.p12"), options: [.atomic])
        try profileRaw.write(to: dir.appendingPathComponent("profile.mobileprovision"), options: [.atomic])

        let record = CertificateRecord(
            id: id,
            displayName: commonName ?? profile.name,
            commonName: commonName ?? "Unknown identity",
            organization: organization ?? "",
            kind: profile.kind,
            teamName: profile.teamName,
            teamID: profile.teamIDs.first ?? profile.applicationIDPrefix,
            certNotBefore: notBefore,
            certNotAfter: notAfter,
            profileName: profile.name,
            profileExpiration: profile.expiration,
            profileCreated: profile.created,
            deviceCount: profile.provisionedDevices.count,
            bundleIDPattern: profile.applicationIDBundle,
            addedAt: Date()
        )
        KeychainStore.set(password, for: id.uuidString)
        certificates.append(record)
        certificates.sort { ($0.effectiveExpiration ?? .distantFuture) < ($1.effectiveExpiration ?? .distantFuture) }
        persist()
        return record
    }

    func remove(_ record: CertificateRecord) {
        KeychainStore.delete(for: record.id.uuidString)
        try? FileManager.default.removeItem(at: Paths.certs.appendingPathComponent(record.id.uuidString))
        certificates.removeAll { $0.id == record.id }
        persist()
    }

    // MARK: p12 inspection (Security framework, public API)

    private func inspectP12(_ data: Data, password: String) throws -> (commonName: String?, organization: String?, notBefore: Date?, notAfter: Date?) {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)

        if status == errSecAuthFailed || status == errSecPkcs12VerifyFailure {
            throw CertificateError.wrongPassword
        }
        guard status == errSecSuccess, let imported = items as? [[String: Any]],
              let first = imported.first else {
            throw CertificateError.invalidP12
        }

        var commonName: String?
        var organization: String?
        var notBefore: Date?
        var notAfter: Date?

        if let chain = first[kSecImportItemCertChain as String] as? [Any],
           let leafAny = chain.first {
            let leaf = leafAny as! SecCertificate
            (commonName, organization, notBefore, notAfter) = Self.certificateFacts(leaf)
        }
        return (commonName, organization, notBefore, notAfter)
    }

    /// Extracts subject/validity facts by walking the certificate DER
    /// (the SecCertificate property APIs are macOS-only).
    static func certificateFacts(_ certificate: SecCertificate) -> (String?, String?, Date?, Date?) {
        let data = SecCertificateCopyData(certificate) as Data
        let facts = CertDER.facts(from: data)
        return (facts.commonName, facts.organization, facts.notBefore, facts.notAfter)
    }
}
