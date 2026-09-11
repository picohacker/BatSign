//
//  SignEngine.swift
//  BatSign
//
//  Swift wrapper over the vendored zsign engine (via BatSignBridge).
//

import Foundation

struct SignRequest {
    var inputIPA: URL
    var outputIPA: URL
    var certificate: CertificateRecord?
    var password: String?
    var adhoc = false
    var entitlementsXML: String?   // custom entitlements plist content (optional)
    var bundleID: String?
    var version: String?
    var displayName: String?
    var minVersion: String?
    var iconPNG: URL?              // replacement app icon (optional)
    var infoPlistOverridesXML: String?  // XML plist merged over Info.plist (optional)
    var dylibs: [URL] = []
    var removeExtensions = false
    var removeWatch = false
    var removeProvision = false
    var removeSupportedDevices = false
    var weakInject = false
    var zipLevel: Int32 = 9
}

enum SignEngineError: LocalizedError {
    case engine(Int32)

    var errorDescription: String? {
        switch self {
        case .engine(let code):
            switch code {
            case -1: return "Invalid input: the file is not a usable .ipa, or an injected dylib is not a valid Mach-O."
            case -2: return "The certificate or provisioning profile could not be loaded (wrong password, or a mismatched pair?)."
            case -3: return "The app payload could not be extracted."
            case -4: return "Signing failed — check the log for the engine's error output."
            case -5: return "No Payload/<App>.app found after signing."
            case -6: return "Packing the signed app into an .ipa failed."
            default: return "Signing engine failed with code \(code)."
            }
        }
    }
}

enum SignEngine {
    /// Keeps every C string alive until the engine call returns.
    private final class CStringPool {
        private var pointers: [UnsafeMutablePointer<CChar>] = []

        func add(_ string: String?) -> UnsafePointer<CChar>? {
            guard let string else { return nil }
            guard let pointer = strdup(string) else { return nil }
            pointers.append(pointer)
            return UnsafePointer(pointer)
        }

        deinit {
            pointers.forEach { free($0) }
        }
    }

    private final class LogSink {
        let handler: (String) -> Void
        init(_ handler: @escaping (String) -> Void) { self.handler = handler }
    }

    /// Runs the engine synchronously on the calling thread.
    /// `onLog` receives every engine log line in order.
    static func sign(_ request: SignRequest, onLog: @escaping (String) -> Void) throws {
        try FileManager.default.createDirectory(at: Paths.temp, withIntermediateDirectories: true)

        let pool = CStringPool()
        let sink = Unmanaged.passRetained(LogSink(onLog))
        defer { sink.release() }

        batsign_set_log_callback({ line, context in
            guard let line, let context else { return }
            let sink = Unmanaged<LogSink>.fromOpaque(context).takeUnretainedValue()
            sink.handler(String(cString: line))
        }, sink.toOpaque())
        defer { batsign_set_log_callback(nil, nil) }

        var entitlementsFile: URL?
        if let xml = request.entitlementsXML, !xml.isEmpty {
            let file = Paths.temp.appendingPathComponent("entitlements-\(UUID().uuidString).plist")
            try xml.data(using: .utf8)?.write(to: file, options: [.atomic])
            entitlementsFile = file
        }
        var plistOverridesFile: URL?
        if let xml = request.infoPlistOverridesXML, !xml.isEmpty {
            let file = Paths.temp.appendingPathComponent("plist-overrides-\(UUID().uuidString).xml")
            try xml.data(using: .utf8)?.write(to: file, options: [.atomic])
            plistOverridesFile = file
        }

        let input = pool.add(request.inputIPA.path)
        let output = pool.add(request.outputIPA.path)
        let p12 = pool.add(request.certificate?.p12URL.path)
        let profile = pool.add(request.certificate?.profileURL.path)
        let password = pool.add(request.password)
        let entitlements = pool.add(entitlementsFile?.path)
        let bundleID = pool.add(request.bundleID)
        let version = pool.add(request.version)
        let displayName = pool.add(request.displayName)
        let minVersion = pool.add(request.minVersion)
        let tempFolder = pool.add(Paths.temp.path)
        let icon = pool.add(request.iconPNG?.path)
        let plistOverrides = pool.add(plistOverridesFile?.path)

        let dylibPointers: [UnsafePointer<CChar>?] = request.dylibs.map { pool.add($0.path) }

        let result = batsign_sign_ipa(
            input, output,
            p12, profile, password,
            entitlements,
            bundleID, version, displayName, minVersion,
            dylibPointers, Int32(dylibPointers.count),
            nil, 0,
            request.adhoc ? 1 : 0,
            request.weakInject ? 1 : 0,
            request.removeExtensions ? 1 : 0,
            request.removeWatch ? 1 : 0,
            request.removeProvision ? 1 : 0,
            request.removeSupportedDevices ? 1 : 0,
            0, // enable documents (off)
            request.zipLevel,
            tempFolder,
            icon,
            plistOverrides
        )

        guard result == BATSIGN_OK else {
            throw SignEngineError.engine(result)
        }
    }
}
