import SwiftUI
import Charts

struct MemoryUsageGraphView: View {
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
                    .foregroundStyle(Color.cyan)
                    .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Timestamp", sample.timestamp),
                        y: .value("Memory (MB)", sample.megabytes)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
            }
        }
    }
}
