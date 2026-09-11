//
//  AppsView.swift
//  BatSign
//
//  App library grid with multi-select bulk sign / bulk delete, plus the
//  per-app detail screen and SignOS-style source browser entry point.
//

import SwiftUI

/// Distinct navigation value types so app pushes, browse pushes and job
/// pushes never collide inside one NavigationStack.
struct AppNavID: Hashable { let id: UUID }
struct JobNavID: Hashable { let id: UUID }
struct BrowseNavID: Hashable { let id: UUID }

struct AppsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var certManager: CertificateManager
    @EnvironmentObject private var notificationHub: NotificationHub

    @State private var showImporter = false
    @State private var importError: String?
    @State private var importing = false
    @State private var sheetApp: AppRecord?

    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var confirmBulkDelete = false
    @State private var showBulkConfig = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            if library.apps.isEmpty {
                EmptyState(icon: "square.grid.2x2",
                           title: "No apps yet",
                           message: "Import an .ipa from the Files app to start your library.")
            } else {
                grid
                bulkBar
            }
        }
        .navigationTitle(selecting ? "\(selection.count) selected" : "Apps")
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if selecting {
                        selecting = false
                        selection.removeAll()
                    } else {
                        showImporter = true
                    }
                } label: {
                    Image(systemName: selecting ? "xmark" : "plus")
                }
                .disabled(importing)
            }
            ToolbarItem(placement: .navigation) {
                if !library.apps.isEmpty {
                    Button {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                        Haptics.tap()
                    } label: {
                        Text(selecting ? "Done" : "Select")
                    }
                }
            }
        }
        .navigationDestination(for: AppNavID.self) { value in
            if let app = library.app(with: value.id) {
                AppDetailView(app: app)
            }
        }
        .navigationDestination(for: BrowseNavID.self) { value in
            if let app = library.app(with: value.id) {
                SourceBrowserView(app: app)
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: FileKind.ipa, title: "Import IPA") { urls in
                showImporter = false
                guard let url = urls.first else { return }
                if let problem = FileKind.validateIPA(url) {
                    importError = problem
                    return
                }
                importing = true
                Task { @MainActor in
                    defer { importing = false }
                    do {
                        let record = try await library.importApp(from: url)
                        Haptics.success()
                        sheetApp = record
                    } catch {
                        importError = error.localizedDescription
                        Haptics.error()
                    }
                }
            } onCancel: {
                showImporter = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $sheetApp) { app in
            SignConfigSheet(app: app)
        }
        .sheet(isPresented: $showBulkConfig) {
            BulkSignConfigSheet(appIDs: Array(selection)) {
                showBulkConfig = false
                selecting = false
                selection.removeAll()
            }
        }
        .confirmationDialog("Delete \(selection.count) app\(selection.count == 1 ? "" : "s") and their files?",
                            isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) {
                for id in selection {
                    if let app = library.app(with: id) {
                        library.remove(app)
                    }
                }
                selection.removeAll()
                selecting = false
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil },
                                                     set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(library.apps) { app in
                Button {
                    if selecting {
                        toggleSelection(app.id)
                        Haptics.tap()
                    }
                } label: {
                    AppGridCard(app: app,
                                icon: library.icon(for: app),
                                signed: !jobQueue.jobs(forApp: app.id).filter { $0.status == .succeeded }.isEmpty,
                                selecting: selecting,
                                selected: selection.contains(app.id))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        selecting = true
                        selection = [app.id]
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        selecting = true
                        selection = [app.id]
                        Haptics.tap()
                    }
                )
                .onTapGesture {
                    if selecting {
                        toggleSelection(app.id)
                        Haptics.tap()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selection.contains(app.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selection.contains(app.id) ? .batAmber : .white.opacity(0.4))
                            .padding(10)
                    }
                }
                .background(
                    NavigationLink(value: AppNavID(id: app.id)) { EmptyView() }
                        .opacity(selecting ? 0 : 1)
                )
            }
        }
        .padding(18)
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    // MARK: Bulk bar

    @ViewBuilder
    private var bulkBar: some View {
        if selecting && !selection.isEmpty {
            HStack(spacing: 10) {
                Button {
                    guard certManager.certificates.isEmpty == false else { return }
                    showBulkConfig = true
                    Haptics.tap()
                } label: {
                    Label("Sign \(selection.count)", systemImage: "signature")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x1A1204))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(LinearGradient(colors: [Color.batAmber, Color.batAmberDeep],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(certManager.certificates.isEmpty)

                Button {
                    confirmBulkDelete = true
                    Haptics.tap()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if selecting && certManager.certificates.isEmpty {
            Text("Import a certificate before bulk signing.")
                .font(.caption)
                .foregroundStyle(.batAmber)
                .padding(.bottom, 6)
        }
    }
}

struct AppGridCard: View {
    let app: AppRecord
    let icon: UIImage?
    let signed: Bool
    var selecting: Bool = false
    var selected: Bool = false

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
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? Color.batAmber : .clear, lineWidth: 2)
        )
        .glassSurface(cornerRadius: 22)
    }
}

// MARK: - Bulk sign configuration

struct BulkSignConfigSheet: View {
    @EnvironmentObject private var certManager: CertificateManager
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var notificationHub: NotificationHub
    @Environment(\.dismiss) private var dismiss

    let appIDs: [UUID]
    var onQueued: (() -> Void)?

    @State private var selectedCertID: UUID?
    @State private var cloneSuffix = true
    @State private var removeExtensions = false
    @State private var removeWatch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        SectionHeader(title: "Certificate")
                        VStack(spacing: 10) {
                            ForEach(certManager.certificates) { cert in
                                Button {
                                    selectedCertID = cert.id
                                    Haptics.tap()
                                } label: {
                                    CertRow(cert: cert, selected: cert.id == selectedCertID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(spacing: 6) {
                        SectionHeader(title: "Bulk options")
                        VStack(spacing: 14) {
                            GlassToggle(title: "Unique bundle ID suffix",
                                        subtitle: "Appends .bulk-XXXX to each bundle ID so installs don't collide",
                                        isOn: $cloneSuffix)
                            Divider().overlay(.white.opacity(0.08))
                            GlassToggle(title: "Remove app extensions", subtitle: nil, isOn: $removeExtensions)
                            Divider().overlay(.white.opacity(0.08))
                            GlassToggle(title: "Remove watch apps", subtitle: nil, isOn: $removeWatch)
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)
                    }

                    Text("\(appIDs.count) app\(appIDs.count == 1 ? "" : "s") will be queued and signed one by one. Track progress in Jobs.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)

                    Button {
                        queueAll()
                    } label: {
                        Label("Queue \(appIDs.count) job\(appIDs.count == 1 ? "" : "s")", systemImage: "signature")
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())
                    .disabled(selectedCertID == nil)
                }
                .padding(18)
            }
            .background(.clear)
            .navigationTitle("Bulk sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if selectedCertID == nil {
                    selectedCertID = certManager.certificates.first?.id
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func queueAll() {
        guard let certID = selectedCertID,
              let cert = certManager.certificate(with: certID) else { return }
        let password = certManager.password(for: cert)
        var queued = 0
        for appID in appIDs {
            guard let app = library.app(with: appID) else { continue }
            let bundleID = cloneSuffix ? "\(app.bundleID).bulk-\(String(UUID().uuidString.prefix(4)).lowercased())" : nil
            let options = SignOptions(
                bundleID: bundleID,
                displayName: nil,
                version: nil,
                minVersion: nil,
                entitlementsXML: nil,
                infoPlistOverridesXML: nil,
                iconFileName: nil,
                removeExtensions: removeExtensions,
                removeWatch: removeWatch,
                removeProvision: false,
                removeSupportedDevices: false,
                weakInject: false,
                dylibNames: []
            )
            jobQueue.enqueue(app: app, cert: cert, password: password,
                             adhoc: false, options: options, dylibs: [], iconURL: nil)
            queued += 1
        }
        notificationHub.post(kind: .info,
                             title: "Bulk sign queued",
                             body: "\(queued) job\(queued == 1 ? "" : "s") queued with \(cert.teamName.isEmpty ? cert.displayName : cert.teamName).",
                             dedupeKey: "")
        Haptics.success()
        onQueued?()
        dismiss()
    }
}

// MARK: - App detail

struct AppDetailView: View {
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var jobQueue: JobQueue
    @Environment(\.dismiss) private var dismiss

    @State var app: AppRecord
    @State private var confirmDelete = false
    @State private var showSignSheet = false

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
                    SectionHeader(title: "Actions")
                    NavigationLink(value: BrowseNavID(id: app.id)) {
                        Label("Browse files (source viewer)", systemImage: "folder.badge.gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .glassSurface(cornerRadius: 18)

                    Button {
                        showSignSheet = true
                    } label: {
                        Label("Sign this app", systemImage: "signature")
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())

                    ShareLink(item: app.fileURL) {
                        Label("Share original .ipa", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .glassSurface(cornerRadius: 18)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Remove from library", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .glassSurface(cornerRadius: 18)
                }

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
        .navigationDestination(for: BrowseNavID.self) { value in
            if let fresh = library.app(with: value.id) {
                SourceBrowserView(app: fresh)
            }
        }
        .sheet(isPresented: $showSignSheet) {
            SignConfigSheet(app: app)
        }
    }
}
