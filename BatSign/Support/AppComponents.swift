//
//  Shared app/cert components (extracted from the former SignView).
//

import SwiftUI

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
        .glassSurface(cornerRadius: 20)
    }
}
