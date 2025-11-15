import SwiftUI

struct EnvironmentSectionView: View {
    @Binding var verbose: Bool
    @Binding var includeSyncBenchmarks: Bool
    @Binding var statelessSelection: Set<ZenzStatelessModelVariant>
    @Binding var statefulSelection: Set<ZenzStatefulModelVariant>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Environment")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Adjust logging and choose which Core ML models stay resident before running cases. All toggles start off to avoid loading every package.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $verbose) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verbose generation logs")
                        .font(.body.weight(.semibold))
                    Text("Mirrors Core ML generation logs into the console when enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Stateless models")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(ZenzStatelessModelVariant.allCases, id: \.self) { variant in
                    Toggle(isOn: statelessBinding(for: variant)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.uiTitle)
                                .font(.body.weight(.semibold))
                            Text(variant.uiDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                }
            }

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Stateful models")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(ZenzStatefulModelVariant.allCases, id: \.self) { variant in
                    Toggle(isOn: statefulBinding(for: variant)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.uiTitle)
                                .font(.body.weight(.semibold))
                            Text(variant.uiDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.accentColor)
                }
            }

            Divider()
                .padding(.vertical, 6)

            Toggle(isOn: $includeSyncBenchmarks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include sync benchmarks")
                        .font(.body.weight(.semibold))
                    Text("Runs legacy on-main benchmarks for debugging. Keep off for keyboard builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.accentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func statelessBinding(for variant: ZenzStatelessModelVariant) -> Binding<Bool> {
        Binding(
            get: { statelessSelection.contains(variant) },
            set: { isOn in
                if isOn {
                    statelessSelection.insert(variant)
                } else {
                    statelessSelection.remove(variant)
                }
            }
        )
    }

    private func statefulBinding(for variant: ZenzStatefulModelVariant) -> Binding<Bool> {
        Binding(
            get: { statefulSelection.contains(variant) },
            set: { isOn in
                if isOn {
                    statefulSelection.insert(variant)
                } else {
                    statefulSelection.remove(variant)
                }
            }
        )
    }
}
