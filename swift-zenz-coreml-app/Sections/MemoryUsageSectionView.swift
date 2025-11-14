import SwiftUI
import Charts

struct MemoryUsageSectionView: View {
    let samples: [MemorySample]
    let currentMegabytes: Double?
    var chartHeight: CGFloat = 160

    private var formattedCurrent: String {
        guard let currentMegabytes else { return "--" }
        return String(format: "%.1f MB", currentMegabytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current memory")
                    .font(.body.weight(.semibold))
                Spacer()
                Text(formattedCurrent)
                    .font(.body.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            if samples.isEmpty {
                Text("Sampling memory usage…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Timestamp", sample.timestamp),
                        y: .value("Memory (MB)", sample.megabytes)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.cyan)
                    .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Timestamp", sample.timestamp),
                        y: .value("Memory (MB)", sample.megabytes)
                    )
                    .foregroundStyle(Gradient(colors: [.cyan.opacity(0.35), .clear]))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let mb = value.as(Double.self) {
                                Text("\(Int(mb)) MB")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
            }
        }
        .padding(.vertical, 8)
    }
}
