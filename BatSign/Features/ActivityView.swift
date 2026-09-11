//
//  ActivityView.swift
//  BatSign
//

import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var notificationHub: NotificationHub

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if jobQueue.jobs.isEmpty {
                    EmptyState(icon: "tray.full",
                               title: "No signing activity",
                               message: "Queued and finished signing jobs appear here with full engine logs.")
                } else {
                    ForEach(jobQueue.jobs) { job in
                        NavigationLink(value: JobNavID(id: job.id)) {
                            JobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !jobQueue.jobs.isEmpty {
                    Button {
                        jobQueue.clearFinished()
                    } label: {
                        Text("Clear finished jobs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.vertical, 6)
                    }
                }

                notificationsCard
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle("Activity")
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            notificationHub.markAllRead()
        }
        .navigationDestination(for: JobNavID.self) { value in
            JobDetailView(jobID: value.id)
        }
    }

    private var notificationsCard: some View {
        Group {
            if !notificationHub.notifications.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Notifications")
                        Spacer()
                        Button {
                            notificationHub.clearAll()
                        } label: {
                            Text("Clear")
                                .font(.caption)
                                .foregroundStyle(.batAmber)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(notificationHub.notifications.prefix(12)) { notification in
                            NotificationRow(notification: notification)
                            if notification.id != notificationHub.notifications.prefix(12).last?.id {
                                Divider().overlay(.white.opacity(0.06))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }
}

struct JobRow: View {
    let job: SignJob

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "app.badge.fill")
                    .font(.title3)
                    .foregroundStyle(.batAmber)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.appName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(job.certName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer()
                StatusChip(status: job.status)
            }
            if job.status == .running {
                ProgressView()
                    .tint(.batAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 42)
            }
            HStack {
                Text(job.stage)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let finished = job.finishedAt {
                    Text(finished.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.leading, 42)
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }
}

struct NotificationRow: View {
    let notification: AppNotification

    private var symbol: String {
        switch notification.kind {
        case .jobSucceeded: return "checkmark.seal.fill"
        case .jobFailed: return "xmark.octagon.fill"
        case .certExpiring, .certExpired: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch notification.kind {
        case .jobSucceeded: return .success
        case .jobFailed: return .danger
        case .certExpiring: return .batAmber
        case .certExpired: return .danger
        case .info: return .white.opacity(0.6)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(notification.date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(notification.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }
}

struct JobDetailView: View {
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var certManager: CertificateManager
    @Environment(\.dismiss) private var dismiss

    let jobID: UUID

    var body: some View {
        Group {
            if let job = jobQueue.job(with: jobID) {
                content(job: job)
            } else {
                EmptyState(icon: "questionmark.circle", title: "Job not found", message: "")
            }
        }
        .background(.clear)
        .navigationTitle("Signing job")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(job: SignJob) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                statusCard(job: job)

                if let error = job.errorMessage {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                logConsole(job: job)

                if let output = jobQueue.outputURL(for: job) {
                    ShareLink(item: output, preview: SharePreview("signed-\(job.appName).ipa")) {
                        Label("Share signed .ipa", systemImage: "square.and.arrow.up.fill")
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())
                }

                if job.status == .failed || job.status == .interrupted {
                    Button {
                        jobQueue.rerun(jobID: job.id)
                    } label: {
                        Label("Re-run job", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())
                }

                if job.status != .running {
                    Button(role: .destructive) {
                        jobQueue.remove(jobID: job.id)
                        dismiss()
                    } label: {
                        Text("Remove job")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.danger)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                    .glassSurface(cornerRadius: 16)
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
    }

    private func statusCard(job: SignJob) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.appName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(job.certName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                StatusChip(status: job.status)
            }
            if job.status == .running {
                ProgressView()
                    .tint(.batAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                InfoRow(label: "Stage", value: job.stage)
            }
            if let started = job.startedAt, let finished = job.finishedAt {
                InfoRow(label: "Duration",
                        value: Duration.seconds(finished.timeIntervalSince(started)).formatted(.units(allowed: [.seconds, .minutes], width: .abbreviated)))
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }

    private func logConsole(job: SignJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Engine log")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if job.log.isEmpty {
                            Text(job.status == .queued ? "Waiting for the engine…" : "No log output.")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        ForEach(Array(job.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 320)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .onChange(of: job.log.count) { _, _ in
                    withAnimation(.linear(duration: 0.12)) {
                        proxy.scrollTo(job.log.count - 1, anchor: .bottom)
                    }
                }
                .onAppear {
                    if !job.log.isEmpty {
                        proxy.scrollTo(job.log.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}
