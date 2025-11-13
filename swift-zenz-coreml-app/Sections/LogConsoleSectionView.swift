import SwiftUI

struct LogConsoleSectionView: View {
    let log: String
    let logScrollID: String
    let isLogEmpty: Bool
    let clearAction: () -> Void
    let shareAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(role: .destructive, action: clearAction) {
                    Label {
                        Text("Clear")
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(tint: .red, labelColor: .red))
                .disabled(isLogEmpty)

                Button(action: shareAction) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(tint: Color.accentColor, labelColor: Color.accentColor))
                .disabled(isLogEmpty)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LogTextView(text: log)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .id(logScrollID)
                }
                .frame(height: 220)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear {
                    proxy.scrollTo(logScrollID, anchor: .bottom)
                }
                .onChange(of: log) { _ in
                    proxy.scrollTo(logScrollID, anchor: .bottom)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
}
