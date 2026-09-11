//
//  FileTypes.swift
//  BatSign
//
//  Central UTType sets and extension validation for every picker.
//

import Foundation
import UniformTypeIdentifiers

enum FileKind {
    /// .ipa (falls back to zip so picks always list archives, even before
    /// our imported UTI registers with LaunchServices).
    static var ipa: [UTType] {
        let ipa = UTType(filenameExtension: "ipa") ?? .zip
        return ipa == .zip ? [.zip] : [ipa, .zip]
    }

    static var p12: [UTType] { [UTType(filenameExtension: "p12") ?? .data] }
    static var profile: [UTType] { [UTType(filenameExtension: "mobileprovision") ?? .data] }
    static var tweak: [UTType] { [.data] }
    static var icon: [UTType] { [.png] }

    static func validateIPA(_ url: URL) -> String? {
        url.pathExtension.lowercased() == "ipa" ? nil : "'\(url.lastPathComponent)' is not an .ipa file."
    }

    static func validateP12(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return (ext == "p12" || ext == "pfx") ? nil : "'\(url.lastPathComponent)' is not a .p12 certificate."
    }

    static func validateProfile(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return (ext == "mobileprovision" || ext == "provisionprofile") ? nil : "'\(url.lastPathComponent)' is not a provisioning profile."
    }
}
