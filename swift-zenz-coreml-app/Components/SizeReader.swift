import SwiftUI

struct SizeReader: View {
    @Binding var size: CGSize
    
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { size = proxy.size }
                .onChange(of: proxy.size) { size = $0 }
        }
    }
}
