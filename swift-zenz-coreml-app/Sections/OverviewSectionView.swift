import SwiftUI

struct OverviewSectionView: View {
    let casesCount: Int
    let envReady: Bool
    let verboseOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Measure Core ML decoding latency with the bundled tokenizer and model assets across 23 curated kana prompts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                StatPill(title: "Cases", value: "\(casesCount)")
                StatPill(
                    title: "Environment",
                    value: envReady ? "Ready" : "Loading…",
                    tint: envReady ? .green : .orange,
                    icon: envReady ? "checkmark.circle.fill" : "hourglass"
                )
                StatPill(title: "Verbose", value: verboseOn ? "On" : "Off")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    var tint: Color? = nil
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint ?? .primary)
                }
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint ?? .primary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
