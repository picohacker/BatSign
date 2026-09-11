//
//  SignSheet.swift
//  BatSign
//
//  The single signing flow, presented as a sheet from anywhere:
//  library apps, imported IPAs, and Discover (store) apps alike.
//

import SwiftUI
import UniformTypeIdentifiers

struct SignConfigSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var certManager: CertificateManager
    @EnvironmentObject private var jobQueue: JobQueue
    @Environment(\.dismiss) private var dismiss

    let app: AppRecord

    @State private var selectedCertID: UUID?
    @State private var showCertList = false
    @State private var showOptions = false
    @State private var showTweakImporter = false
    @State private var showIconImporter = false
    @State private var importError: String?

    @State private var adhoc = false
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
    @State private var editInfoPlist = false
    @State private var infoPlistXML = ""
    @State private var showInfoPlistEditor = false
    @State private var iconURL: URL?
    @State private var dylibs: [URL] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    appCard
                    certSection
                    optionsSection
                    signButton
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AuroraBackground())
            .navigationTitle("Sign \"\(app.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: presetDefaults)
            .sheet(isPresented: $showCertList) { certPickerSheet }
            .sheet(isPresented: $showOptions) { optionsSheet }
            .sheet(isPresented: $showEntitlementsEditor) { entitlementsSheet }
            .sheet(isPresented: $showInfoPlistEditor) { infoPlistSheet }
            .sheet(isPresented: $showTweakImporter) {
                DocumentPicker(contentTypes: FileKind.tweak, allowsMultipleSelection: true, title: "Add tweaks (.deb / .dylib)") { urls in
                    showTweakImporter = false
                    handleTweakImport(.success(urls))
                } onCancel: {
                    showTweakImporter = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showIconImporter) {
                DocumentPicker(contentTypes: FileKind.icon, title: "Choose replacement icon") { urls in
                    showIconImporter = false
                    handleIconImport(.success(urls))
                } onCancel: {
                    showIconImporter = false
                }
                .ignoresSafeArea()
            }
            .alert("Something needs fixing", isPresented: Binding(get: { importError != nil },
                                                                  set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedCert: CertificateRecord? {
        adhoc ? nil : selectedCertID.flatMap { certManager.certificate(with: $0) } ?? certManager.certificates.first
    }

    // MARK: Sections

    private var appCard: some View {
        HStack(spacing: 14) {
            AppIconView(icon: library.icon(for: app), fallbackSymbol: "app.gift")
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Text("\(app.versionLabel) · \(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }

    private var certSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Certificate")
            Button {
                showCertList = true
                Haptics.tap()
            } label: {
                HStack(spacing: 12) {
                    // Same visual identity as the picker rows: one logo everywhere.
                    if adhoc {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.10))
                            Image(systemName: "signature")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: 42, height: 42)
                    } else {
                        ExpiryRing(daysRemaining: selectedCert?.daysRemaining, size: 42)
                    }
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
                            Text("No certificate")
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
                .padding(14)
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 20)
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    if activeOptionCount > 0 {
                        Text("\(activeOptionCount) active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.batAmber)
                    } else {
                        Text("Default")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 20)
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
        if editInfoPlist && !infoPlistXML.isEmpty { count += 1 }
        if iconURL != nil { count += 1 }
        if !dylibs.isEmpty { count += 1 }
        return count
    }

    private var signButton: some View {
        Button {
            startSigning()
        } label: {
            Text("Sign")
        }
        .buttonStyle(PrimaryGlassButtonStyle())
    }

    // MARK: Sheets (cert list)

    private var certPickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(certManager.certificates) { cert in
                        Button {
                            selectedCertID = cert.id
                            adhoc = false
                            showCertList = false
                            Haptics.tap()
                        } label: {
                            CertRow(cert: cert, selected: cert.id == selectedCert?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        adhoc = true
                        showCertList = false
                        Haptics.tap()
                    } label: {
                        HStack {
                            Image(systemName: "signature")
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
            .background(AuroraBackground())
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCertList = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sheets (options)

    private var optionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        SectionHeader(title: "Identity overrides")
                        VStack(spacing: 10) {
                            GlassTextField(placeholder: "Display name", icon: "character.cursor.ibeam", text: $displayName, autocapitalization: .words)
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

                    advancedSection
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(AuroraBackground())
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

    private var advancedSection: some View {
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
                        optionRow(icon: "list.bullet.rectangle",
                                  title: entitlementsXML.isEmpty ? "Edit entitlements…" : "Entitlements loaded")
                    }
                }
                Divider().overlay(.white.opacity(0.08))
                GlassToggle(title: "Edit Info.plist",
                            subtitle: "Merge your own keys into the app's Info.plist", isOn: $editInfoPlist)
                if editInfoPlist {
                    Button {
                        if infoPlistXML.isEmpty {
                            infoPlistXML = Self.defaultInfoPlistXML(for: app) ?? ""
                        }
                        showInfoPlistEditor = true
                    } label: {
                        optionRow(icon: "doc.text.magnifyingglass",
                                  title: infoPlistXML.isEmpty ? "Edit Info.plist…" : "Info.plist overrides loaded")
                    }
                }
                Divider().overlay(.white.opacity(0.08))
                Button {
                    showIconImporter = true
                } label: {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                            .foregroundStyle(.batAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replace app icon")
                                .font(.subheadline.weight(.medium))
                            Text(iconURL?.lastPathComponent ?? "Pick a PNG to swap in")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        Spacer()
                        if iconURL != nil {
                            Button {
                                iconURL = nil
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.danger)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(.white.opacity(0.08))
                HStack {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .foregroundStyle(.batAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inject tweaks")
                            .font(.subheadline.weight(.medium))
                        Text(dylibs.isEmpty ? "Add .deb packages or .dylib files"
                             : dylibs.map { $0.lastPathComponent }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        showTweakImporter = true
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

    private func optionRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
        }
        .font(.subheadline)
        .foregroundStyle(.batAmber)
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

    private var infoPlistSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Top-level keys you keep here are merged into the app's Info.plist before signing.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 18)
                TextEditor(text: $infoPlistXML)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
            }
            .background(.clear)
            .navigationTitle("Info.plist overrides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        infoPlistXML = Self.defaultInfoPlistXML(for: app) ?? ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let data = infoPlistXML.data(using: .utf8),
                           (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil {
                            importError = "Info.plist overrides are not a valid XML plist."
                            infoPlistXML = ""
                            editInfoPlist = false
                        }
                        showInfoPlistEditor = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Logic

    private func presetDefaults() {
        if selectedCertID == nil {
            // Auto-sign flow: prefer the last certificate the user signed with,
            // falling back to the first available one — one tap to Sign.
            let lastID = UUID(uuidString: UserDefaults.standard.string(forKey: "lastCertID") ?? "")
            if let lastID, certManager.certificate(with: lastID) != nil {
                selectedCertID = lastID
            } else {
                selectedCertID = certManager.certificates.first?.id
            }
        }
        removeExtensions = app.hasExtensions
        removeWatch = app.hasWatchApp
    }

    private func handleTweakImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ext == "dylib" {
                    if !dylibs.contains(url) { dylibs.append(url) }
                    continue
                }
                guard ext == "deb" else {
                    importError = "Tweaks must be .deb packages or .dylib files."
                    continue
                }
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let workDir = Paths.temp.appendingPathComponent("tweak-\(UUID().uuidString)", isDirectory: true)
                    let names = try DebUnpacker.extractDylibs(from: url, into: workDir)
                    if names.isEmpty {
                        importError = "'\(url.lastPathComponent)' contains no .dylib files."
                    } else {
                        for name in names {
                            let extracted = workDir.appendingPathComponent(name)
                            if !dylibs.contains(extracted) { dylibs.append(extracted) }
                        }
                        Haptics.success()
                    }
                } catch {
                    importError = error.localizedDescription
                    Haptics.error()
                }
            }
        }
    }

    private func handleIconImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            iconURL = url
            Haptics.tap()
        }
    }

    static func defaultInfoPlistXML(for app: AppRecord) -> String? {
        guard let reader = try? ZipReader(url: app.fileURL),
              let entry = reader.firstEntry(matching: { $0.name == "Payload/\(app.bundleFileName).app/Info.plist" }),
              let data = try? reader.readData(entry),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return nil
        }
        return String(data: xmlData, encoding: .utf8)
    }

    private func startSigning() {
        guard selectedCert != nil || adhoc else {
            showCertList = true
            return
        }
        if customEntitlements {
            if let data = entitlementsXML.data(using: .utf8),
               (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil {
                importError = "Custom entitlements are not a valid plist."
                return
            }
        }
        if editInfoPlist {
            if let data = infoPlistXML.data(using: .utf8),
               (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) == nil {
                importError = "Info.plist overrides are not a valid plist."
                return
            }
        }

        let options = SignOptions(
            bundleID: bundleID.isEmpty ? nil : bundleID,
            displayName: displayName.isEmpty ? nil : displayName,
            version: version.isEmpty ? nil : version,
            minVersion: minVersion.isEmpty ? nil : minVersion,
            entitlementsXML: customEntitlements ? entitlementsXML : nil,
            infoPlistOverridesXML: editInfoPlist ? infoPlistXML : nil,
            iconFileName: nil,
            removeExtensions: removeExtensions,
            removeWatch: removeWatch,
            removeProvision: removeProvision,
            removeSupportedDevices: removeDevices,
            weakInject: false,
            dylibNames: dylibs.enumerated().map { "\($0.offset)-\($0.element.lastPathComponent)" }
        )

        jobQueue.enqueue(app: app, cert: selectedCert,
                         adhoc: adhoc, options: options, dylibs: dylibs,
                         iconURL: iconURL)
        dismiss()
        appState.selectedTab = .activity
    }
}
