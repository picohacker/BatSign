//
//  SignView.swift
//  BatSign
//

import SwiftUI
import UniformTypeIdentifiers

struct SignView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var certManager: CertificateManager
    @EnvironmentObject private var jobQueue: JobQueue

    @State private var showImporter = false
    @State private var showCertPicker = false
    @State private var showOptions = false
    @State private var showDylibImporter = false
    @State private var importError: String?
    @State private var importing = false

    @State private var selectedCertID: UUID?
    @State private var adhoc = false

    // Options
    @State private var displayName = ""
    @State private var bundleID = ""
    @State private var version = ""
    @State private var minVersion = ""
    @State private var removeExtensions = false
    @State private var removeWatch = false
    @State private var removeProvision = false
    @State private var removeDevices = false
    @State private var customEntitlements = false
    @State private var entitlementsXML = ""
    @State private var showEntitlementsEditor = false
    @State private var dylibs: [URL] = []

    private var selectedApp: AppRecord? {
        appState.selectedAppID.flatMap { library.app(with: $0) } ?? library.apps.first
    }

    private var selectedCert: CertificateRecord? {
        adhoc ? nil : selectedCertID.flatMap { certManager.certificate(with: $0) } ?? certManager.certificates.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                appSection
                certSection
                optionsSection
                signButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .navigationTitle("Sign")
        .navigationBarTitleDisplayMode(.large)
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [ipaType],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showDylibImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            handleDylibImport(result)
        }
        .sheet(isPresented: $showCertPicker) { certPickerSheet }
        .sheet(isPresented: $showOptions) { optionsSheet }
        .sheet(isPresented: $showEntitlementsEditor) { entitlementsSheet }
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

    // MARK: Sections

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "App")
            Button {
                showImporter = true
                Haptics.tap()
            } label: {
                if let app = selectedApp {
                    AppSummaryCard(app: app, icon: library.icon(for: app))
                } else {
                    ImportPromptCard(importing: importing)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var certSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Certificate")
            Button {
                showCertPicker = true
                Haptics.tap()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: adhoc ? "waveform.path" : "seal.fill")
                        .font(.title3)
                        .foregroundStyle(adhoc ? Color.white.opacity(0.5) : .batAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        if adhoc {
                            Text("Ad-hoc signature")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("No certificate — output won't install on-device")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        } else if let cert = selectedCert {
                            Text(cert.teamName.isEmpty ? cert.displayName : cert.teamName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(cert.kind.label)
                                if let days = cert.daysRemaining {
                                    Text("· \(days)d left")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        } else {
                            Text("No certificate selected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Tap to pick one or go ad-hoc")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 22)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Options")
            Button {
                showOptions = true
                Haptics.tap()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.batAmber)
                    Text("Signing options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    optionsSummary
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 22)
        }
    }

    private var optionsSummary: some View {
        Group {
            if activeOptionCount == 0 {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Text("\(activeOptionCount) active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.batAmber)
            }
        }
    }

    private var activeOptionCount: Int {
        var count = 0
        if !displayName.isEmpty { count += 1 }
        if !bundleID.isEmpty { count += 1 }
        if !version.isEmpty { count += 1 }
        if !minVersion.isEmpty { count += 1 }
        if removeExtensions { count += 1 }
        if removeWatch { count += 1 }
        if removeProvision { count += 1 }
        if removeDevices { count += 1 }
        if customEntitlements && !entitlementsXML.isEmpty { count += 1 }
        if !dylibs.isEmpty { count += 1 }
        return count
    }

    private var signButton: some View {
        Button {
            startSigning()
        } label: {
            Label(selectedCert == nil && !adhoc ? "Choose a certificate" : "Sign & Pack",
                  systemImage: "signature")
        }
        .buttonStyle(PrimaryGlassButtonStyle())
        .disabled(selectedApp == nil)
        .padding(.top, 4)
    }

    // MARK: Sheets

    private var certPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(certManager.certificates) { cert in
                        Button {
                            selectedCertID = cert.id
                            adhoc = false
                            showCertPicker = false
                            Haptics.tap()
                        } label: {
                            CertRow(cert: cert, selected: cert.id == selectedCert?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        adhoc = true
                        showCertPicker = false
                        Haptics.tap()
                    } label: {
                        HStack {
                            Image(systemName: "waveform.path")
                            VStack(alignment: .leading) {
                                Text("Ad-hoc (no certificate)")
                                    .font(.subheadline.weight(.semibold))
                                Text("Unsigned identity — for testing only")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            if adhoc {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.batAmber)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                    .glassSurface(cornerRadius: 20)
                }
                .padding(18)
            }
            .background(.clear)
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCertPicker = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var optionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        SectionHeader(title: "Identity overrides")
                        VStack(spacing: 10) {
                            GlassTextField(placeholder: "Display name", icon: "character.cursor.ibeam", text: $displayName)
                            GlassTextField(placeholder: "Bundle ID", icon: "shippingbox", text: $bundleID)
                            GlassTextField(placeholder: "Version", icon: "number", text: $version)
                            GlassTextField(placeholder: "Minimum iOS version", icon: "iphone.gen3", text: $minVersion)
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)
                    }

                    VStack(spacing: 6) {
                        SectionHeader(title: "Strip from payload")
                        VStack(spacing: 14) {
                            GlassToggle(title: "Remove app extensions",
                                        subtitle: "PlugIns & widgets that break under a new team", isOn: $removeExtensions)
                            Divider().overlay(.white.opacity(0.08))
                            GlassToggle(title: "Remove watch app",
                                        subtitle: "Companion WatchKit bundles", isOn: $removeWatch)
                            Divider().overlay(.white.opacity(0.08))
                            GlassToggle(title: "Remove embedded profile",
                                        subtitle: "Drop the old embedded.mobileprovision", isOn: $removeProvision)
                            Divider().overlay(.white.opacity(0.08))
                            GlassToggle(title: "Remove UISupportedDevices",
                                        subtitle: "Unlocks newer devices", isOn: $removeDevices)
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)
                    }

                    VStack(spacing: 6) {
                        SectionHeader(title: "Advanced")
                        VStack(spacing: 14) {
                            GlassToggle(title: "Custom entitlements",
                                        subtitle: "Override with a plist of your own", isOn: $customEntitlements)
                            if customEntitlements {
                                Button {
                                    if entitlementsXML.isEmpty, let cert = selectedCert {
                                        entitlementsXML = ProfileParser.entitlementsXML(certManager.entitlements(for: cert)) ?? ""
                                    }
                                    showEntitlementsEditor = true
                                } label: {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle")
                                        Text(entitlementsXML.isEmpty ? "Edit entitlements…" : "Entitlements loaded")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.batAmber)
                                }
                            }
                            Divider().overlay(.white.opacity(0.08))
                            HStack {
                                Image(systemName: "shippingbox.and.arrow.backward")
                                    .foregroundStyle(.batAmber)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Inject dylibs")
                                        .font(.subheadline.weight(.medium))
                                    Text(dylibs.isEmpty ? "Add tweak dylibs to load at launch"
                                         : dylibs.map { $0.lastPathComponent }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.45))
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button {
                                    showDylibImporter = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.batAmber)
                                }
                            }
                            if !dylibs.isEmpty {
                                ForEach(dylibs, id: \.self) { url in
                                    HStack {
                                        Image(systemName: "doc.badge.gearshape")
                                            .font(.caption)
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            dylibs.removeAll { $0 == url }
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .foregroundStyle(.danger)
                                        }
                                    }
                                    .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 22)
                    }
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(.clear)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showOptions = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var entitlementsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $entitlementsXML)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .padding(16)
            }
            .background(.clear)
            .navigationTitle("Entitlements plist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        if let cert = selectedCert {
                            entitlementsXML = ProfileParser.entitlementsXML(certManager.entitlements(for: cert)) ?? ""
                        } else {
                            entitlementsXML = ""
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showEntitlementsEditor = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Actions

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false }
                do {
                    let record = try await library.importApp(from: url)
                    appState.selectedAppID = record.id
                    resetIdentityOptions(for: record)
                    Haptics.success()
                } catch {
                    importError = error.localizedDescription
                    Haptics.error()
                }
            }
        }
    }

    private func handleDylibImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls where url.pathExtension.lowercased() == "dylib" {
                if !dylibs.contains(url) { dylibs.append(url) }
            }
        }
    }

    private func resetIdentityOptions(for app: AppRecord) {
        displayName = ""
        bundleID = ""
        version = ""
        minVersion = ""
        removeExtensions = app.hasExtensions
        removeWatch = app.hasWatchApp
        removeProvision = false
        removeDevices = false
        customEntitlements = false
        entitlementsXML = ""
        dylibs = []
    }

    private func startSigning() {
        guard let app = selectedApp else { return }
        guard selectedCert != nil || adhoc else {
            showCertPicker = true
            return
        }
        if customEntitlements {
            // Validate plist before queueing; a broken plist is a wasted job.
            if let data = entitlementsXML.data(using: .utf8),
               (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil {
                importError = "Custom entitlements are not a valid plist."
                return
            }
        }

        let options = SignOptions(
            bundleID: bundleID.isEmpty ? nil : bundleID,
            displayName: displayName.isEmpty ? nil : displayName,
            version: version.isEmpty ? nil : version,
            minVersion: minVersion.isEmpty ? nil : minVersion,
            entitlementsXML: customEntitlements ? entitlementsXML : nil,
            removeExtensions: removeExtensions,
            removeWatch: removeWatch,
            removeProvision: removeProvision,
            removeSupportedDevices: removeDevices,
            weakInject: false,
            dylibNames: dylibs.enumerated().map { "\($0.offset)-\($0.element.lastPathComponent)" }
        )

        let password = selectedCert.flatMap { certManager.password(for: $0) }
        jobQueue.enqueue(app: app, cert: selectedCert, password: password,
                         adhoc: adhoc, options: options, dylibs: dylibs)
        appState.selectedTab = .activity
    }
}

// MARK: - Cards

struct AppSummaryCard: View {
    let app: AppRecord
    let icon: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(icon: icon, fallbackSymbol: "app.gift")
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(app.versionLabel)
                    if !app.architectures.isEmpty {
                        Text(app.architectures.joined(separator: "/"))
                    }
                    Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(16)
    }
}

struct ImportPromptCard: View {
    let importing: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.batAmber.opacity(0.55))
                    .frame(width: 54, height: 54)
                Image(systemName: importing ? "hourglass" : "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.batAmber)
            }
            Text(importing ? "Reading package…" : "Import an .ipa")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Files app, AirDrop, or any provider")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct AppIconView: View {
    let icon: UIImage?
    let fallbackSymbol: String

    var body: some View {
        if let icon {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                )
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: fallbackSymbol)
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.4))
                )
        }
    }
}

struct CertRow: View {
    let cert: CertificateRecord
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ExpiryRing(daysRemaining: cert.daysRemaining, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(cert.teamName.isEmpty ? cert.displayName : cert.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Chip(text: cert.kind.label,
                         color: cert.kind == .development ? .batAmber : (cert.kind == .enterprise ? .success : .white.opacity(0.6)))
                    if let expiry = cert.effectiveExpiration {
                        Text("exp " + expiry.formatted(.dateTime.day().month().year()))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.batAmber)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20, interactive: true)
    }
}
