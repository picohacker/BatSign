//
//  Storage.swift
//  BatSign
//
//  Filesystem layout + atomic JSON persistence for records.
//

import Foundation

enum Paths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var apps: URL { make(documents.appendingPathComponent("Apps", isDirectory: true)) }
    static var certs: URL { make(documents.appendingPathComponent("Certificates", isDirectory: true)) }
    static var jobs: URL { make(documents.appendingPathComponent("Jobs", isDirectory: true)) }
    static var data: URL { make(documents.appendingPathComponent("Data", isDirectory: true)) }
    static var temp: URL {
        make(FileManager.default.temporaryDirectory.appendingPathComponent("Signing", isDirectory: true))
    }

    static var jobsIndex: URL { data.appendingPathComponent("jobs.json") }
    static var appsIndex: URL { data.appendingPathComponent("apps.json") }
    static var certsIndex: URL { data.appendingPathComponent("certs.json") }
    static var sourcesIndex: URL { data.appendingPathComponent("sources.json") }
    static var notificationsStore: URL { data.appendingPathComponent("notifications.json") }

    private static func make(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum JSONStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            BLog.app.error("Failed to decode \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            BLog.app.error("Failed to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
