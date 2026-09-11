//
//  BackgroundKeeper.swift
//  BatSign
//
//  Keeps BatSign current in the background:
//  - BGAppRefreshTask: certificate expiry checks + notification upkeep
//  - BGProcessingTask: same maintenance when the system grants more time
//  - A user-initiated activity token keeps the device awake during signing
//
//  iOS limits how long any app may run in the background; these are the
//  sanctioned mechanisms and they are used honestly (no audio/location hacks).
//

import Foundation
import BackgroundTasks
import UIKit

final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    static let refreshID = "app.batsign.refresh"
    static let processingID = "app.batsign.processing"

    private init() {}

    /// Must be called before didFinishLaunching returns.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { [weak self] task in
            self?.handle(task: task)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingID, using: nil) { [weak self] task in
            self?.handle(task: task)
        }
    }

    func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshID)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: Self.processingID)
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        processing.requiresExternalPower = false
        processing.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(processing)
    }

    private func handle(task: BGTask) {
        schedule() // keep the chain alive

        // The expiration handler and the normal path can both fire; iOS
        // treats a second setTaskCompleted as an error, so complete exactly once.
        let completed = CompletionGuard()
        let work = Task { [weak self] in
            await self?.runMaintenance()
            completed.run { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            work.cancel()
            completed.run { task.setTaskCompleted(success: false) }
        }
    }

    @MainActor
    private func runMaintenance() async {
        NotificationHub.shared.checkCertificateExpiries(CertificateManager.shared.certificates)
    }
}

/// Thread-safe run-at-most-once helper.
final class CompletionGuard {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if !done {
            done = true
            body()
        }
    }
}
