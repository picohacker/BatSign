//
//  Components.swift
//  BatSign
//
//  Shared Liquid Glass building blocks.
//

import SwiftUI

// MARK: - Bat glyph (brand)

struct BatGlyph: View {
    var size: CGFloat = 28
    var color: Color = .batAmber

    var body: some View {
        BatShape()
            .fill(color)
            .frame(width: size, height: size * 0.62)
    }
}

struct BatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        p.move(to: pt(0.56, 0.0))
        p.addLine(to: pt(0.50, 0.22))
        p.addLine(to: pt(0.44, 0.0))
        p.addCurve(to: pt(0.42, 0.62),
                   control1: pt(0.42, 0.15), control2: pt(0.41, 0.44))
        p.addCurve(to: pt(0.0, 0.19),
                   control1: pt(0.30, 0.36), control2: pt(0.16, 0.02))
        p.addCurve(to: pt(0.12, 0.95),
                   control1: pt(0.05, 0.68), control2: pt(0.06, 0.92))
        p.addCurve(to: pt(0.38, 0.75),
                   control1: pt(0.20, 0.94), control2: pt(0.29, 0.66))
        p.addCurve(to: pt(0.46, 1.0),
                   control1: pt(0.44, 1.1), control2: pt(0.46, 1.05))
        p.addLine(to: pt(0.54, 1.0))
        p.addCurve(to: pt(0.62, 0.75),
                   control1: pt(0.54, 1.05), control2: pt(0.56, 1.1))
        p.addCurve(to: pt(0.88, 0.95),
                   control1: pt(0.71, 0.66), control2: pt(0.80, 0.94))
        p.addCurve(to: pt(1.0, 0.19),
                   control1: pt(0.94, 0.92), control2: pt(0.95, 0.68))
        p.addCurve(to: pt(0.58, 0.62),
                   control1: pt(0.84, 0.02), control2: pt(0.70, 0.36))
        p.addCurve(to: pt(0.56, 0.0),
                   control1: pt(0.59, 0.44), control2: pt(0.58, 0.15))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cards & rows

struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var copyable: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    Haptics.tap()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
    }
}

struct Chip: View {
    let text: String
    var color: Color = .batAmber

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.30))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Expiry ring

struct ExpiryRing: View {
    let daysRemaining: Int?
    var size: CGFloat = 40

    private var fraction: Double {
        guard let days = daysRemaining else { return 0 }
        return min(1.0, Double(days) / 365.0)
    }

    private var color: Color {
        guard let days = daysRemaining else { return .gray }
        if days <= 0 { return .danger }
        if days <= 7 { return .danger }
        if days <= 21 { return .batAmber }
        return .success
    }

    private var label: String {
        guard let days = daysRemaining else { return "–" }
        if days <= 0 { return "0" }
        return "\(days)"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Glass text fields

struct GlassTextField: View {
    let placeholder: String
    var icon: String
    var text: Binding<String>
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization? = .never

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Toggles

struct GlassToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .tint(.batAmber)
    }
}

// MARK: - Status chip for jobs

struct StatusChip: View {
    let status: JobStatus

    private var color: Color {
        switch status {
        case .queued: return .white.opacity(0.5)
        case .running: return .batAmber
        case .succeeded: return .success
        case .failed: return .danger
        case .interrupted: return .orange
        }
    }

    var body: some View {
        Label(status.label, systemImage: {
            switch status {
            case .queued: return "clock"
            case .running: return "waveform.path"
            case .succeeded: return "checkmark.seal.fill"
            case .failed: return "xmark.octagon.fill"
            case .interrupted: return "pause.circle.fill"
            }
        }())
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }
}
