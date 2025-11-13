import SwiftUI

struct EnvironmentSectionView: View {
    @Binding var verbose: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $verbose) {
                Text("Verbose generation logs")
                    .font(.body.weight(.semibold))
            }
            .toggleStyle(.switch)
            .tint(.accentColor)

            Text("Mirrors Core ML generation logs into the console when enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
