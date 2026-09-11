//
//  Theme.swift
//  BatSign
//
//  Liquid Glass design system: tokens, glass surfaces, aurora background.
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Design tokens, exposed as ShapeStyle members so `.batAmber` etc. work in
/// every `foregroundStyle`/`stroke`/gradient context.
extension ShapeStyle where Self == Color {
    static var batAmber: Color { Color(hex: 0xFFC53D) }
    static var batAmberDeep: Color { Color(hex: 0xFF9F0A) }
    static var glassStroke: Color { Color.white.opacity(0.14) }
    static var danger: Color { Color(hex: 0xFF5D5D) }
    static var success: Color { Color(hex: 0x4ADE80) }
}

// MARK: - Glass surface

/// The core Liquid Glass surface. Uses the native `glassEffect` on iOS 26+
/// and a faithful material/stroke fallback on earlier versions.
/// Note: `.interactive()` is deliberately NOT used — on custom-tapped rows it
/// can interfere with hit-testing; the system tab bar gets interactivity for free.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.glassStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Aurora background

/// Animated mesh-gradient aurora that lives behind every glass surface.
struct AuroraBackground: View {
    @State private var phase: Float = 0

    private let palette: [Color] = [
        Color(hex: 0x0B0D14), Color(hex: 0x141A2A),
        Color(hex: 0x1C1633), Color(hex: 0x0F1D24),
        Color(hex: 0x231A10), Color(hex: 0x12141F),
        Color(hex: 0x1A1026), Color(hex: 0x0D1620),
        Color(hex: 0x101828),
    ]

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: points, colors: palette)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x0B0D14), Color(hex: 0x141A2A), Color(hex: 0x0B0D14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
        }
        .overlay(
            Circle()
                .fill(
                    RadialGradient(colors: [Color.batAmber.opacity(0.10), .clear],
                                   center: .center, startRadius: 0, endRadius: 320)
                )
                .frame(width: 640, height: 640)
                .offset(x: 60 + CGFloat(sin(phase) * 40), y: -140 + CGFloat(cos(phase * 0.8) * 36))
                .ignoresSafeArea()
        )
        .onAppear { startTimer() }
    }

    private var points: [SIMD2<Float>] {
        let s = phase
        let base: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5, 0.5], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
        let drifts: [SIMD2<Float>] = [
            [0.02, -0.01], [0.0, 0.02], [-0.02, 0.01],
            [0.01, 0.0], [0.03, 0.03], [-0.01, -0.02],
            [0.02, 0.01], [-0.02, 0.02], [0.0, -0.01],
        ]
        return zip(base, drifts).map { basePoint, drift in
            SIMD2<Float>(basePoint.x + drift.x * sin(s + basePoint.y * 6),
                         basePoint.y + drift.y * cos(s * 0.9 + basePoint.x * 6))
        }
    }

    private func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 1 / 24, repeats: true) { _ in
            phase += 0.012
        }
    }
}

// MARK: - Buttons

struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(Color(hex: 0x1A1204))
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.batAmber, Color.batAmberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
