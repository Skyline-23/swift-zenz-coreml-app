import SwiftUI

struct BenchmarkSectionView: View {
    let casesCount: Int
    let isRunning: Bool
    let envReady: Bool
    let runAll: () -> Void
    let runShort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preset suites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose a mode for the \(casesCount)-sentence kana corpus.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: runAll) {
                    Label(isRunning ? "Running…" : "Run Full Set", systemImage: "aqi.medium")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(tint: .cyan, labelColor: .cyan))
                .disabled(isRunning || !envReady)

                Button(action: runShort) {
                    Label("Short Burst", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(tint: .cyan, labelColor: .cyan))
                .disabled(isRunning || !envReady)
            }
        }
    }
}
