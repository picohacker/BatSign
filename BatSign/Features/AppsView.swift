//
//  AppsView.swift
//  BatSign
//

import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var certManager: CertificateManager

    @State private var showImporter = false
    @State private var importError: String?
    @State private var importing = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            if library.apps.isEmpty {
                EmptyState(icon: "square.grid.2x2",
                           title: "No apps yet",
                           message: "Import an .ipa from the Files app to start your library.")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(library.apps) { app in
                        NavigationLink(value: AppNavID(id: app.id)) {
                            AppGridCard(app: app, icon: library.icon(for: app),
                                        signed: !jobQueue.jobs(forApp: app.id).filter { $0.status == .succeeded }.isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Apps")
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: AppNavID.self) { value in
            if let app = library.app(with: value.id) {
                AppDetailView(app: app)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [ipaType],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .failure(let error): importError = error.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                importing = true
                Task { @MainActor in
                    defer { importing = false }
                    do {
                        _ = try await library.importApp(from: url)
                        Haptics.success()
                    } catch {
                        importError = error.localizedDescription
                        Haptics.error()
                    }
                }
            }
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil },
                                                     set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var ipaType: UTType {
        UTType("app.batsign.ipa") ?? UTType(filenameExtension: "ipa") ?? .data
    }
}

struct AppGridCard: View {
    let app: AppRecord
    let icon: UIImage?
    let signed: Bool

    var body: some View {
        VStack(spacing: 10) {
            AppIconView(icon: icon, fallbackSymbol: "app.gift")
                .frame(width: 62, height: 62)
            VStack(spacing: 2) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(app.versionLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            if signed {
                Chip(text: "SIGNED", color: .success)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 22, interactive: true)
    }
}

/// Distinct navigation value types so app pushes and job pushes never collide.
struct AppNavID: Hashable { let id: UUID }
struct JobNavID: Hashable { let id: UUID }

struct AppDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var jobQueue: JobQueue
    @Environment(\.dismiss) private var dismiss

    @State var app: AppRecord
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    AppIconView(icon: library.icon(for: app), fallbackSymbol: "app.gift")
                        .frame(width: 86, height: 86)
                    VStack(spacing: 4) {
                        Text(app.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 8) {
                        if !app.architectures.isEmpty {
                            Chip(text: app.architectures.joined(separator: "/").uppercased())
                        }
                        if app.hasExtensions { Chip(text: "EXTENSIONS", color: .white.opacity(0.55)) }
                        if app.hasWatchApp { Chip(text: "WATCH", color: .white.opacity(0.55)) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .glassSurface(cornerRadius: 26)

                VStack(spacing: 0) {
                    InfoRow(label: "Version", value: app.versionLabel)
                    Divider().overlay(.white.opacity(0.08))
                    InfoRow(label: "Minimum iOS", value: app.minimumOS.isEmpty ? "—" : app.minimumOS)
                    Divider().overlay(.white.opacity(0.08))
                    InfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                    Divider().overlay(.white.opacity(0.08))
                    InfoRow(label: "Bundle file", value: "\(app.bundleFileName).app", mono: true)
                    Divider().overlay(.white.opacity(0.08))
                    InfoRow(label: "Imported", value: app.addedAt.formatted(.dateTime.day().month().year()))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassSurface(cornerRadius: 22)

                VStack(spacing: 10) {
                    SectionHeader(title: "History")
                    if jobQueue.jobs(forApp: app.id).isEmpty {
                        Text("No signing jobs yet.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 10)
                    }
                    ForEach(jobQueue.jobs(forApp: app.id).prefix(5)) { job in
                        NavigationLink(value: JobNavID(id: job.id)) {
                            JobRow(job: job)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        appState.signApp(app.id)
                    } label: {
                        Label("Sign this app", systemImage: "signature")
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())

                    ShareLink(item: app.fileURL) {
                        Label("Share original .ipa", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 13)
                    }
                    .glassSurface(cornerRadius: 18, interactive: true)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Remove from library", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .glassSurface(cornerRadius: 18, interactive: true)
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(.clear)
        .confirmationDialog("Remove \(app.name) and its file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                library.remove(app)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(for: JobNavID.self) { value in
            JobDetailView(jobID: value.id)
        }
    }
}
