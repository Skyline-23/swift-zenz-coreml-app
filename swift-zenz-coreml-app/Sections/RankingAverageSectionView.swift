import SwiftUI

struct RankingAverageSectionView: View {
    let averages: [BenchmarkAverage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if averages.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No aggregated results yet. Run a benchmark to see averages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                ForEach(averages) { metric in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.variant)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        Text("\(metric.samples) samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.3f s", metric.average))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                }
            }
        }
        .padding(.vertical, 4)
    }
}
