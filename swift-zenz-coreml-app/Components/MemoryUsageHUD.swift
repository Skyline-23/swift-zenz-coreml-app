import SwiftUI
import Charts

struct MemoryUsageHUD: View {
    let currentMegabytes: Double?
    let samples: [MemorySample]
    let isExpanded: Bool

    private var compactValueText: String {
        guard let currentMegabytes else { return "--" }
        return String(format: "%.0f", currentMegabytes)
    }

    private var expandedValueText: String {
        guard let currentMegabytes else { return "-- MB" }
        return String(format: "%.1f MB", currentMegabytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            HStack(alignment: .center, spacing: isExpanded ? 14 : 4) {
                Image(systemName: "memorychip")
                    .font(isExpanded ? .title3.weight(.semibold) : .footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .padding(.all, isExpanded ? 10 : 4)
                    .background(
                        RoundedRectangle(cornerRadius: isExpanded ? 14 : 9, style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                    .transition(.opacity)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(expandedValueText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Current memory usage")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(compactValueText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .layoutPriority(1)
                        Text("MB")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if isExpanded {
                    Spacer(minLength: 0)
                }
            }

            if isExpanded {
                Divider()
                    .blendMode(.overlay)
                    .transition(.opacity)

                MemoryUsageSparkline(samples: samples)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
    }
}

private struct MemoryUsageSparkline: View {
    let samples: [MemorySample]

    var body: some View {
        Group {
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
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
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
                .frame(height: 220)
            }
        }
    }
}
