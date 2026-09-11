//
//  CertificatesView.swift
//  BatSign
//

import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
    @EnvironmentObject private var certManager: CertificateManager
    @State private var showImport = false

    var body: some View {
        ScrollView {
            if certManager.certificates.isEmpty {
                EmptyState(icon: "seal",
                           title: "No certificates",
                           message: "Import your Apple .p12 identity and its provisioning profile to sign apps.")
            } else {
                VStack(spacing: 12) {
                    ForEach(certManager.certificates) { cert in
                        NavigationLink(value: AppNavID(id: cert.id)) {
                            CertRow(cert: cert)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Certs")
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImport = true } label: { Image(systemName: "plus") }
            }
        }
        .navigationDestination(for: AppNavID.self) { value in
            if let cert = certManager.certificate(with: value.id) {
                CertificateDetailView(cert: cert)
            }
        }
        .sheet(isPresented: $showImport) {
            CertificateImportSheet()
        }
    }
}

struct CertificateImportSheet: View {
    @EnvironmentObject private var certManager: CertificateManager
    @Environment(\.dismiss) private var dismiss

    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var password = ""
    @State private var showP12Picker = false
    @State private var showProfilePicker = false
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    fileSlot(title: "Identity (.p12)",
                             subtitle: "Developer or distribution identity",
                             url: p12URL, symbol: "key.fill") { showP12Picker = true }

                    fileSlot(title: "Provisioning profile (.mobileprovision)",
                             subtitle: "Must match the identity's team",
                             url: profileURL, symbol: "doc.badge.gearshape") { showProfilePicker = true }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "p12 password")
                        SecureField("Password", text: $password)
                            .font(.subheadline)
                            .padding(14)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                            .foregroundStyle(.white)
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        importNow()
                    } label: {
                        Label(working ? "Validating…" : "Import certificate",
                              systemImage: working ? "hourglass" : "seal.fill")
                    }
                    .buttonStyle(PrimaryGlassButtonStyle())
                    .disabled(p12URL == nil || profileURL == nil || password.isEmpty || working)
                }
                .padding(18)
            }
            .background(.clear)
            .navigationTitle("Add certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showP12Picker) {
                DocumentPicker(contentTypes: FileKind.p12, title: "Choose .p12 identity") { urls in
                    showP12Picker = false
                    guard let url = urls.first else { return }
                    if let problem = FileKind.validateP12(url) {
                        error = problem
                    } else {
                        p12URL = url
                    }
                } onCancel: {
                    showP12Picker = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showProfilePicker) {
                DocumentPicker(contentTypes: FileKind.profile, title: "Choose provisioning profile") { urls in
                    showProfilePicker = false
                    guard let url = urls.first else { return }
                    if let problem = FileKind.validateProfile(url) {
                        error = problem
                    } else {
                        profileURL = url
                    }
                } onCancel: {
                    showProfilePicker = false
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fileSlot(title: String, subtitle: String, url: URL?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: url != nil ? "checkmark.circle.fill" : symbol)
                    .font(.title3)
                    .foregroundStyle(url != nil ? .success : .batAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(url?.lastPathComponent ?? subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "folder")
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .glassSurface(cornerRadius: 20)
    }

    private func importNow() {
        guard let p12URL, let profileURL else { return }
        working = true
        error = nil
        Task { @MainActor in
            defer { working = false }
            do {
                let record = try certManager.importCertificate(p12URL: p12URL,
                                                               profileURL: profileURL,
                                                               password: password)
                NotificationHub.shared.post(kind: .info,
                                            title: "Certificate imported",
                                            body: "\(record.teamName.isEmpty ? record.displayName : record.teamName) · \(record.kind.label)",
                                            dedupeKey: "cert-added:\(record.id)")
                NotificationHub.shared.checkCertificateExpiries(certManager.certificates)
                Haptics.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                Haptics.error()
            }
        }
    }
}

struct CertificateDetailView: View {
    @EnvironmentObject private var certManager: CertificateManager
    @Environment(\.dismiss) private var dismiss

    @State var cert: CertificateRecord
    @State private var confirmDelete = false
    @State private var showDevices = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if cert.daysRemaining != nil && cert.daysRemaining! <= 7 {
                    Label(cert.isExpired ? "This certificate has expired." : "Expires in \(cert.daysRemaining ?? 0) days — import a fresh pair soon.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                infoCard
                entitlementsCard
                devicesCard

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete certificate", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .glassSurface(cornerRadius: 18)
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle(cert.teamName.isEmpty ? cert.displayName : cert.teamName)
        .navigationBarTitleDisplayMode(.inline)
        .background(.clear)
        .confirmationDialog("Delete this certificate?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                certManager.remove(cert)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var aps: String {
        (certManager.entitlements(for: cert)["aps-environment"] as? String) ?? ""
    }

    private var header: some View {
        HStack(spacing: 16) {
            ExpiryRing(daysRemaining: cert.daysRemaining, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Chip(text: cert.kind.label)
                Text(cert.teamName.isEmpty ? cert.displayName : cert.teamName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let expiry = cert.effectiveExpiration {
                    Text("Valid until \(expiry.formatted(.dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(18)
        .glassSurface(cornerRadius: 24)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Common name", value: cert.commonName)
            Divider().overlay(.white.opacity(0.08))
            if !cert.organization.isEmpty {
                InfoRow(label: "Organization", value: cert.organization)
                Divider().overlay(.white.opacity(0.08))
            }
            InfoRow(label: "Team", value: cert.teamName.isEmpty ? "—" : cert.teamName)
            Divider().overlay(.white.opacity(0.08))
            InfoRow(label: "Team ID", value: cert.teamID.isEmpty ? "—" : cert.teamID, mono: true, copyable: true)
            Divider().overlay(.white.opacity(0.08))
            InfoRow(label: "Bundle pattern", value: cert.bundleIDPattern.isEmpty ? "—" : cert.bundleIDPattern, mono: true)
            Divider().overlay(.white.opacity(0.08))
            InfoRow(label: "Devices", value: cert.kind == .enterprise ? "All (enterprise)" : "\(cert.deviceCount)")
            Divider().overlay(.white.opacity(0.08))
            InfoRow(label: "Profile", value: cert.profileName)
            if !aps.isEmpty {
                Divider().overlay(.white.opacity(0.08))
                InfoRow(label: "Push (APS)", value: aps)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 22)
    }

    private var entitlements: [(String, String)] {
        certManager.entitlements(for: cert)
            .compactMap { key, value -> (String, String)? in
                let valueText: String
                switch value {
                case let b as Bool: valueText = b ? "true" : "false"
                case let s as String: valueText = s
                case let arr as [Any]: valueText = "\(arr.count) item\(arr.count == 1 ? "" : "s")"
                default: valueText = "\(value)"
                }
                return (key, valueText)
            }
            .sorted { $0.0 < $1.0 }
    }

    private var entitlementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Entitlements from profile")
            VStack(spacing: 0) {
                ForEach(entitlements, id: \.0) { key, value in
                    InfoRow(label: key, value: value, mono: true)
                    if key != entitlements.last?.0 {
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
                if entitlements.isEmpty {
                    Text("No entitlements found in this profile.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var devicesCard: some View {
        Group {
            if cert.kind == .development && cert.deviceCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showDevices.toggle()
                        }
                    } label: {
                        HStack {
                            SectionHeader(title: "Provisioned devices (\(cert.deviceCount))")
                            Spacer()
                            Image(systemName: showDevices ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                    if showDevices {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(certManager.devices(for: cert), id: \.self) { device in
                                Text(device)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(14)
                .glassSurface(cornerRadius: 22)
            }
        }
    }
}
