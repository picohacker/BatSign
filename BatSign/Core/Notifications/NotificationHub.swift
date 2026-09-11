//
//  NotificationHub.swift
//  BatSign
//
//  Instant, synced in-app + system notifications.
//  Every notification is persisted (so it survives relaunches), deduplicated
//  by key, delivered to the system center immediately, and shown as a banner
//  even while the app is in the foreground.
//

import Foundation
import UserNotifications

struct AppNotification: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case jobSucceeded
        case jobFailed
        case certExpiring
        case certExpired
        case info
    }

    let id: UUID
    var key: String            // dedupe key ("" = never dedupe)
    var kind: Kind
    var title: String
    var body: String
    var date: Date
    var isRead: Bool
}

final class NotificationHub: ObservableObject {
    static let shared = NotificationHub()

    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published var systemDeliveryEnabled: Bool = true

    private let center = UNUserNotificationCenter.current()

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        notifications = JSONStore.load([AppNotification].self, from: Paths.notificationsStore) ?? []
        recalcUnread()
    }

    private func persist() {
        JSONStore.save(notifications, to: Paths.notificationsStore)
    }

    private func recalcUnread() {
        unreadCount = notifications.filter { !$0.isRead }.count
    }

    // MARK: Posting

    /// Posts a notification to the in-app hub and the system center instantly.
    func post(kind: AppNotification.Kind, title: String, body: String, dedupeKey: String = "") {
        DispatchQueue.main.async {
            if !dedupeKey.isEmpty,
               let existing = self.notifications.firstIndex(where: { $0.key == dedupeKey && !$0.isRead }) {
                self.notifications[existing].date = Date()
                self.notifications[existing].title = title
                self.notifications[existing].body = body
            } else {
                let notification = AppNotification(id: UUID(), key: dedupeKey,
                                                   kind: kind, title: title, body: body,
                                                   date: Date(), isRead: false)
                self.notifications.insert(notification, at: 0)
            }
            if self.notifications.count > 200 {
                self.notifications = Array(self.notifications.prefix(200))
            }
            self.persist()
            self.recalcUnread()
            self.deliverSystemNotification(kind: kind, title: title, body: body, key: dedupeKey)
        }
    }

    private func deliverSystemNotification(kind: AppNotification.Kind, title: String, body: String, key: String) {
        guard systemDeliveryEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        switch kind {
        case .jobSucceeded: content.interruptionLevel = .active
        case .jobFailed: content.interruptionLevel = .timeSensitive
        case .certExpiring: content.interruptionLevel = .active
        case .certExpired: content.interruptionLevel = .timeSensitive
        case .info: content.interruptionLevel = .active
        }

        let request = UNNotificationRequest(identifier: key.isEmpty ? UUID().uuidString : key,
                                            content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                BLog.app.error("System notification failed: \(error.localizedDescription)")
            }
        }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.systemDeliveryEnabled = granted
                if let error {
                    BLog.app.error("Notification auth: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Read state

    func markRead(_ notification: AppNotification) {
        DispatchQueue.main.async {
            guard let index = self.notifications.firstIndex(where: { $0.id == notification.id }) else { return }
            self.notifications[index].isRead = true
            self.persist()
            self.recalcUnread()
        }
    }

    func markAllRead() {
        DispatchQueue.main.async {
            for index in self.notifications.indices {
                self.notifications[index].isRead = true
            }
            self.persist()
            self.recalcUnread()
        }
    }

    func clearAll() {
        DispatchQueue.main.async {
            self.notifications.removeAll()
            self.persist()
            self.recalcUnread()
        }
    }

    // MARK: Certificate expiry watch

    private static let expiryThresholds = [14, 7, 3, 1, 0]

    /// Checks all certificates and posts deduplicated warnings. Called on
    /// launch, on foreground, and from background refresh tasks.
    func checkCertificateExpiries(_ certificates: [CertificateRecord]) {
        let now = Date()
        for cert in certificates {
            guard let expiry = cert.effectiveExpiration else { continue }
            let days = Calendar.current.dateComponents([.day],
                                                       from: Calendar.current.startOfDay(for: now),
                                                       to: Calendar.current.startOfDay(for: expiry)).day ?? 0

            if days <= 0 {
                post(kind: .certExpired,
                     title: "Certificate expired",
                     body: "\(cert.teamName.isEmpty ? cert.displayName : cert.teamName) expired. Signed apps will fail to install until it is renewed.",
                     dedupeKey: "expiry:\(cert.id):expired")
                continue
            }
            for threshold in Self.expiryThresholds where days <= threshold {
                post(kind: .certExpiring,
                     title: "Certificate expires in \(days) day\(days == 1 ? "" : "s")",
                     body: "\(cert.teamName.isEmpty ? cert.displayName : cert.teamName) · \(cert.kind.label). Import a fresh p12 + profile to stay ahead of it.",
                     dedupeKey: "expiry:\(cert.id):\(threshold)")
                break
            }
        }
    }
}
