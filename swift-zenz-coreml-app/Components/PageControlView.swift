import SwiftUI

struct PageControlView: UIViewRepresentable {
    let totalPages: Int
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.onValueChanged(_:)),
            for: .valueChanged
        )
        pageControl.hidesForSinglePage = true
        pageControl.currentPageIndicatorTintColor = UIColor.tintColor
        pageControl.pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.3)
        return pageControl
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.numberOfPages = totalPages
        let clamped = min(max(0, currentPage), max(0, totalPages - 1))
        if uiView.currentPage != clamped {
            uiView.currentPage = clamped
        }
        uiView.isHidden = totalPages <= 1
    }

    final class Coordinator: NSObject {
        let parent: PageControlView

        init(parent: PageControlView) {
            self.parent = parent
        }

        @objc
        func onValueChanged(_ sender: UIPageControl) {
            parent.currentPage = sender.currentPage
        }
    }
}
