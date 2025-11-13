import SwiftUI

struct StatusOutputSectionView: View {
    let statusEntry: StructuredEntry?
    let outputEntries: [StructuredEntry]
    @Binding var selectedPage: Int
    @Binding var cardHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let statusEntry {
                    StatusCardView(entry: statusEntry)
                } else {
                    StatusPlaceholderView()
                }
            }
            .padding(.horizontal, 16)

            if outputEntries.isEmpty {
                OutputPlaceholderView()
            } else {
                VStack(spacing: 4) {
                    TabView(selection: selectionBinding) {
                        ForEach(Array(outputEntries.enumerated()), id: \.offset) { index, entry in
                            EntryCardView(entry: entry)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(key: OutputCardHeightKey.self, value: proxy.size.height)
                                    }
                                )
                                .tag(index)
                        }
                    }
                    .frame(height: cardHeight)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .never))
                    .onPreferenceChange(OutputCardHeightKey.self) { newHeight in
                        let clamped = min(max(newHeight, 220), 520)
                        if clamped - cardHeight > 1 {
                            cardHeight = clamped
                        }
                    }

                    PageControlView(totalPages: outputEntries.count, currentPage: selectionBinding)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { min(selectedPage, max(0, outputEntries.count - 1)) },
            set: { selectedPage = $0 }
        )
    }
}

private struct OutputCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
