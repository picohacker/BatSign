//
//  JobQueue.swift
//  BatSign
//
//  Persistent signing queue. Jobs survive app relaunches; a serial engine
//  queue signs one app at a time, streams live log output into the UI,
//  posts notifications on completion, and prevents system sleep while a
//  job is running.
//
//  Threading model: the engine runs on a private serial queue; every
//  @Published mutation happens on the main thread. `enqueue`/`rerun` must
//  be called from the main thread.
//

import Foundation
import UIKit

enum JobStatus: String, Codable {
    case queued
    case running
    case succeeded
    case failed
    case interrupted

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Signing"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }
}

struct SignJob: Identifiable, Codable, Hashable {
    let id: UUID
    var appID: UUID
    var appName: String
    var certID: UUID?
    var certName: String
    var adhoc: Bool
    var options: SignOptions
    var status: JobStatus
    var stage: String
    var log: [String]
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?

    var directory: URL { Paths.jobs.appendingPathComponent(id.uuidString, isDirectory: true) }
    var inputURL: URL { directory.appendingPathComponent("input.ipa") }
    var outputURL: URL { directory.appendingPathComponent("signed.ipa") }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SignJob, rhs: SignJob) -> Bool { lhs.id == rhs.id }
}

struct SignOptions: Codable, Hashable {
    var bundleID: String?
    var displayName: String?
    var version: String?
    var minVersion: String?
    var entitlementsXML: String?
    var removeExtensions: Bool
    var removeWatch: Bool
    var removeProvision: Bool
    var removeSupportedDevices: Bool
    var weakInject: Bool
    var dylibNames: [String]
}

final class JobQueue: ObservableObject {
    @Published private(set) var jobs: [SignJob] = []
    @Published private(set) var activeJobID: UUID?

    private let engineQueue = DispatchQueue(label: "app.batsign.engine", qos: .userInitiated)

    init() {
        load()
        recoverInterrupted()
    }

    // MARK: Persistence

    func load() {
        jobs = JSONStore.load([SignJob].self, from: Paths.jobsIndex) ?? []
        jobs.sort { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        JSONStore.save(jobs, to: Paths.jobsIndex)
    }

    /// Jobs that were mid-flight when the app died.
    private func recoverInterrupted() {
        var changed = false
        for index in jobs.indices where jobs[index].status == .running {
            jobs[index].status = .interrupted
            jobs[index].stage = "Interrupted — re-run to continue"
            changed = true
        }
        if changed { persist() }
    }

    // MARK: Queries

    func job(with id: UUID) -> SignJob? {
        jobs.first { $0.id == id }
    }

    func jobs(forApp appID: UUID) -> [SignJob] {
        jobs.filter { $0.appID == appID }
    }

    func outputURL(for job: SignJob) -> URL? {
        (job.status == .succeeded && FileManager.default.fileExists(atPath: job.outputURL.path)) ? job.outputURL : nil
    }

    func isBusy() -> Bool {
        activeJobID != nil
    }

    // MARK: Enqueueing

    /// Main thread only.
    func enqueue(app: AppRecord,
                 cert: CertificateRecord?,
                 password: String?,
                 adhoc: Bool,
                 options: SignOptions,
                 dylibs: [URL]) {
        let job = SignJob(id: UUID(),
                          appID: app.id,
                          appName: app.name,
                          certID: cert?.id,
                          certName: cert?.displayName ?? "Ad-hoc (no certificate)",
                          adhoc: adhoc,
                          options: options,
                          status: .queued,
                          stage: "Waiting in queue",
                          log: [],
                          createdAt: Date(),
                          startedAt: nil,
                          finishedAt: nil,
                          errorMessage: nil)

        do {
            // Snapshot the inputs so deleting the library entry never breaks a queued job.
            try FileManager.default.createDirectory(at: job.directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: job.inputURL.path) {
                try FileManager.default.removeItem(at: job.inputURL)
            }
            try FileManager.default.copyItem(at: app.fileURL, to: job.inputURL)

            var storedDylibs: [URL] = []
            for (index, dylib) in dylibs.enumerated() {
                let scoped = dylib.startAccessingSecurityScopedResource()
                defer { if scoped { dylib.stopAccessingSecurityScopedResource() } }
                let target = job.directory.appendingPathComponent("inject-\(index)-\(dylib.lastPathComponent)")
                try FileManager.default.copyItem(at: dylib, to: target)
                storedDylibs.append(target)
            }

            jobs.insert(job, at: 0)
            persist()
            Haptics.success()
            run(job: job, dylibs: storedDylibs, password: password)
        } catch {
            NotificationHub.shared.post(kind: .jobFailed,
                                        title: "Could not queue \(app.name)",
                                        body: error.localizedDescription,
                                        dedupeKey: "queue:\(job.id)")
        }
    }

    /// Main thread only.
    func rerun(jobID: UUID, password: String?) {
        guard let job = job(with: jobID), job.status != .running, job.status != .queued else { return }
        var fresh = job
        fresh.status = .queued
        fresh.stage = "Waiting in queue"
        fresh.errorMessage = nil
        fresh.finishedAt = nil
        fresh.log = []
        fresh.startedAt = nil
        updateJob(fresh)

        let dylibs = optionsDylibURLs(for: fresh)
        run(job: fresh, dylibs: dylibs, password: password)
    }

    func remove(jobID: UUID) {
        guard let job = job(with: jobID) else { return }
        if job.status == .running { return }
        try? FileManager.default.removeItem(at: job.directory)
        jobs.removeAll { $0.id == jobID }
        persist()
    }

    func clearFinished() {
        for job in jobs where job.status != .running && job.status != .queued {
            try? FileManager.default.removeItem(at: job.directory)
        }
        jobs.removeAll { $0.status != .running && $0.status != .queued }
        persist()
    }

    private func optionsDylibURLs(for job: SignJob) -> [URL] {
        job.options.dylibNames.map { job.directory.appendingPathComponent($0) }
    }

    // MARK: State updates (main thread)

    private func updateJob(_ job: SignJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        persist()
    }

    private func setStage(_ stage: String, for jobID: UUID) {
        guard var job = job(with: jobID) else { return }
        job.stage = stage
        updateJob(job)
    }

    // MARK: Execution

    private func run(job original: SignJob, dylibs: [URL], password: String?) {
        guard var job = job(with: original.id) else { return }
        job.status = .running
        job.startedAt = Date()
        job.stage = "Preparing"
        activeJobID = job.id
        updateJob(job)

        // Capture everything the background pass needs by value.
        let jobID = job.id
        let appName = job.appName
        let certRecord = original.certID.flatMap { CertificateManagerHolder.shared.certificate(with: $0) }
        let options = job.options

        let token: NSObjectProtocol? = UserDefaults.standard.bool(forKey: "preventSleep")
            ? ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                    reason: "BatSign is signing an app")
            : nil

        engineQueue.async { [weak self] in
            defer {
                if let token {
                    ProcessInfo.processInfo.endActivity(token)
                }
                DispatchQueue.main.async { self?.activeJobID = nil }
            }
            let engineLog = EngineLogBuffer { [weak self] fresh in
                guard let self, var job = self.job(with: jobID) else { return }
                job.log = fresh
                self.updateJob(job)
            }
            let setStageOnMain: (String) -> Void = { [weak self] stage in
                DispatchQueue.main.async {
                    self?.setStage(stage, for: jobID)
                }
            }

            let request = SignRequest(
                inputIPA: original.inputURL,
                outputIPA: original.outputURL,
                certificate: certRecord,
                password: password,
                adhoc: original.adhoc,
                entitlementsXML: options.entitlementsXML,
                bundleID: options.bundleID,
                version: options.version,
                displayName: options.displayName,
                minVersion: options.minVersion,
                dylibs: dylibs,
                removeExtensions: options.removeExtensions,
                removeWatch: options.removeWatch,
                removeProvision: options.removeProvision,
                removeSupportedDevices: options.removeSupportedDevices,
                weakInject: options.weakInject
            )

            var failure: Error?
            do {
                try SignEngine.sign(request) { line in
                    engineLog.append(line)
                    if line.contains("Unzipping") {
                        setStageOnMain("Extracting")
                    } else if line.contains("Signing") {
                        setStageOnMain("Signing")
                    } else if line.contains("Archiving") {
                        setStageOnMain("Packing")
                    }
                }
            } catch {
                failure = error
            }

            let finalLog = engineLog.snapshot()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeJobID = nil
                guard var fresh = self.job(with: jobID) else { return }
                fresh.finishedAt = Date()
                fresh.log = finalLog
                if let failure {
                    fresh.status = .failed
                    fresh.stage = "Failed"
                    fresh.errorMessage = failure.localizedDescription
                    self.updateJob(fresh)
                    Haptics.error()
                    NotificationHub.shared.post(
                        kind: .jobFailed,
                        title: "\(appName) failed to sign",
                        body: failure.localizedDescription,
                        dedupeKey: "job:\(jobID)")
                } else {
                    fresh.status = .succeeded
                    fresh.stage = "Signed"
                    self.updateJob(fresh)
                    Haptics.success()
                    NotificationHub.shared.post(
                        kind: .jobSucceeded,
                        title: "\(appName) signed",
                        body: "Ready to install or share.",
                        dedupeKey: "job:\(jobID)")
                }
            }
        }
    }
}

/// Accumulates engine log lines and periodically hands the whole buffer to
/// the main-thread sink.
private final class EngineLogBuffer {
    private let apply: ([String]) -> Void
    private var lines: [String] = []
    private var lastFlush = Date.distantPast
    private let lock = NSLock()

    init(apply: @escaping ([String]) -> Void) {
        self.apply = apply
    }

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        let shouldFlush = Date().timeIntervalSince(lastFlush) > 0.4
        if shouldFlush { lastFlush = Date() }
        let buffer = lines
        lock.unlock()

        if shouldFlush {
            let payload = buffer
            DispatchQueue.main.async { [apply] in
                apply(payload)
            }
        }
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
// (CertificateManagerHolder lives in Core/KeepAlive/BackgroundKeeper.swift.)
