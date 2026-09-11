//
//  RootView.swift
//  BatSign
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationHub: NotificationHub
    @AppStorage("onboarded") private var onboarded = false
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            AuroraBackground()

            TabView(selection: $appState.selectedTab) {
                NavigationStack { DiscoverView() }
                    .tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }
                    .tag(AppState.Tab.discover)

                NavigationStack { AppsView() }
                    .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                    .tag(AppState.Tab.apps)

                NavigationStack { CertificatesView() }
                    .tabItem { Label("Certs", systemImage: "seal") }
                    .tag(AppState.Tab.certs)

                NavigationStack { ActivityView() }
                    .tabItem { Label("Jobs", systemImage: "tray.full") }
                    .badge(notificationHub.unreadCount)
                    .tag(AppState.Tab.activity)

                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppState.Tab.settings)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            showOnboarding = !onboarded
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var notificationHub: NotificationHub
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(colors: [Color.batAmber, Color.batAmberDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                            .shadow(color: .batAmber.opacity(0.45), radius: 30, y: 10)
                        BatGlyph(size: 54, color: Color(hex: 0x1A1204))
                    }
                    VStack(spacing: 8) {
                        Text("BatSign")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("On-device IPA signing. Liquid Glass.\nZero servers, zero tracking.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 40)

                VStack(spacing: 12) {
                    onboardingRow(icon: "signature", title: "Sign any IPA",
                                  body: "Change identity, inject dylibs, strip extensions — powered by zsign, right on your iPhone.")
                    onboardingRow(icon: "seal", title: "Own your certificates",
                                  body: "p12 + mobileprovision stay in your sandbox. Expiry is watched for you.")
                    onboardingRow(icon: "bell.badge", title: "Know instantly",
                                  body: "Live signing progress and instant alerts the moment a job lands.")
                }
                .padding(20)
                .glassSurface(cornerRadius: 28)

                Spacer()

                Button {
                    notificationHub.requestAuthorization()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        onboarded = true
                    }
                } label: {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryGlassButtonStyle())
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
    }

    private func onboardingRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.batAmber)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
