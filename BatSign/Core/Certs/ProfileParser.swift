//
//  ProfileParser.swift
//  BatSign
//
//  Parses embedded.mobileprovision payloads (CMS-wrapped plists) using
//  public APIs only: a plist byte-range scan + PropertyListSerialization.
//

import Foundation

struct ProvisionProfile {
    var name: String
    var teamName: String
    var teamIDs: [String]
    var created: Date?
    var expiration: Date?
    var entitlements: [String: Any]
    var provisionedDevices: [String]
    var provisionsAllDevices: Bool
    var applicationIDPrefix: String
    var applicationIDBundle: String
    var getTaskAllow: Bool
    var apsEnvironment: String

    var kind: CertKind {
        if provisionsAllDevices { return .enterprise }
        if getTaskAllow { return .development }
        return .distribution
    }
}

enum ProfileParser {
    enum ProfileError: LocalizedError {
        case notAProfile
        case badPlist

        var errorDescription: String? {
            switch self {
            case .notAProfile: return "This is not a provisioning profile (embedded.mobileprovision)."
            case .badPlist: return "The provisioning profile payload could not be parsed."
            }
        }
    }

    static func parse(data: Data) throws -> ProvisionProfile {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: [.backwards]),
              start.lowerBound < end.upperBound else {
            throw ProfileError.notAProfile
        }
        let payload = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: payload, options: [], format: nil) as? [String: Any] else {
            throw ProfileError.badPlist
        }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let applicationID = entitlements["application-identifier"] as? String ?? ""
        let appIDParts = applicationID.split(separator: ".", maxSplits: 1).map(String.init)

        var devices: [String] = []
        if let rawDevices = plist["ProvisionedDevices"] as? [Any] {
            devices = rawDevices.map { "\($0)" }
        }

        return ProvisionProfile(
            name: plist["Name"] as? String ?? "Unnamed profile",
            teamName: plist["TeamName"] as? String ?? "",
            teamIDs: plist["TeamIdentifier"] as? [String] ?? [],
            created: plist["CreationDate"] as? Date,
            expiration: plist["ExpirationDate"] as? Date,
            entitlements: entitlements,
            provisionedDevices: devices,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            applicationIDPrefix: appIDParts.first ?? "",
            applicationIDBundle: appIDParts.count > 1 ? appIDParts[1] : "",
            getTaskAllow: entitlements["get-task-allow"] as? Bool ?? false,
            apsEnvironment: entitlements["aps-environment"] as? String ?? ""
        )
    }

    /// Renders the profile's entitlements as an XML plist (used as the
    /// default custom-entitlements template in the signing options).
    static func entitlementsXML(_ entitlements: [String: Any]) -> String? {
        guard !entitlements.isEmpty,
              let data = try? PropertyListSerialization.data(
                fromPropertyList: entitlements, format: .xml, options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
