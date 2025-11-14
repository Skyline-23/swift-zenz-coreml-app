import SwiftUI

struct TestCaseSectionView: View {
    let totalCount: Int
    let browseAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Available Cases")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(totalCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(totalCount == 1 ? "case ready" : "cases ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Manage kana prompts from the Test Case Library when you need to add, edit, or review defaults.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                browseAction()
            } label: {
                Label("Open Test Case Library", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.accentColor)
            }
            .tintedGlassButton(tint: .accentColor, labelColor: .accentColor)

            Button(role: .destructive) {
                resetAction()
            } label: {
                Label("Reset to Default Cases", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.red)
            }
            .tintedGlassButton(tint: .red, labelColor: .red)
        }
    }
}
