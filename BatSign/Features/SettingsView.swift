//
//  SettingsView.swift
//  BatSign
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: AppLibrary
    @EnvironmentObject private var certManager: CertificateManager
    @EnvironmentObject private var jobQueue: JobQueue
    @EnvironmentObject private var notificationHub: NotificationHub

    @AppStorage("preventSleep") private var preventSleep = true
    @AppStorage("systemNotifications") private var systemNotifications = true

    @State private var version = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                brandCard

                VStack(spacing: 6) {
                    SectionHeader(title: "Signing")
                    VStack(spacing: 14) {
                        GlassToggle(title: "Keep device awake while signing",
                                    subtitle: "Prevents mid-sign suspension on large apps",
                                    isOn: $preventSleep)
                        Divider().overlay(.white.opacity(0.08))
                        GlassToggle(title: "System notifications",
                                    subtitle: "Banners even when BatSign is in the foreground",
                                    isOn: $systemNotifications)
                    }
                    .padding(14)
                    .glassSurface(cornerRadius: 22)
                }

                storageCard

                VStack(spacing: 6) {
                    SectionHeader(title: "How installing works")
                    VStack(alignment: .leading, spacing: 10) {
                        installStep("1", text: "Sign and share the .ipa from BatSign.")
                        installStep("2", text: "Install it with SideStore, Feather, AltStore, eSign, or Xcode — any signer that owns your certificate.")
                        installStep("3", text: "BatSign focuses on signing; installation always requires a provisioning identity valid for your device.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .glassSurface(cornerRadius: 22)
                }

                VStack(spacing: 6) {
                    SectionHeader(title: "About")
                    VStack(spacing: 0) {
                        InfoRow(label: "Version", value: version.isEmpty ? "1.0" : version)
                        Divider().overlay(.white.opacity(0.08))
                        InfoRow(label: "Signing engine", value: "zsign (vendored, MIT)")
                        Divider().overlay(.white.opacity(0.08))
                        InfoRow(label: "Crypto", value: "OpenSSL 3.5 (Apache-2.0)")
                        Divider().overlay(.white.opacity(0.08))
                        InfoRow(label: "Telemetry", value: "None. Everything is local.")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassSurface(cornerRadius: 22)
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle("Settings")
        .background(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        }
        .onChange(of: systemNotifications) { _, enabled in
            notificationHub.systemDeliveryEnabled = enabled
            if enabled {
                notificationHub.requestAuthorization()
            }
        }
    }

    private var brandCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.batAmber, Color.batAmberDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                BatGlyph(size: 30, color: Color(hex: 0x1A1204))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("BatSign")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("On-device IPA signer · Liquid Glass")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(16)
        .glassSurface(cornerRadius: 22)
    }

    private var storageCard: some View {
        VStack(spacing: 6) {
            SectionHeader(title: "Storage")
            VStack(spacing: 0) {
                InfoRow(label: "Apps", value: "\(library.apps.count)")
                Divider().overlay(.white.opacity(0.08))
                InfoRow(label: "Certificates", value: "\(certManager.certificates.count)")
                Divider().overlay(.white.opacity(0.08))
                InfoRow(label: "Library size",
                        value: ByteCountFormatter.string(fromByteCount: library.totalBytesUsed(), countStyle: .file))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 22)

            Button {
                jobQueue.clearFinished()
            } label: {
                Label("Clear finished job files", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .glassSurface(cornerRadius: 18, interactive: true)
        }
    }

    private func installStep(_ number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.batAmber)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.batAmber.opacity(0.15)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
