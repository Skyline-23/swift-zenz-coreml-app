import SwiftUI
import Charts

private enum FloatingHUDConstants {
    static let compactIconSize: CGFloat = 20
    static let compactIconPadding: CGFloat = 1
    static let compactSpacing: CGFloat = 8
    static let compactHorizontalPadding: CGFloat = 8
    static let compactVerticalPadding: CGFloat = 10
    static let expandedHeight: CGFloat = 260
    static let expandedWidthMax: CGFloat = 360
    static let horizontalMargin: CGFloat = 8
    static let expansionAnimation = Animation.interactiveSpring(response: 0.27, dampingFraction: 0.7, blendDuration: 0.02)
    static let attachmentAnimation = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.74, blendDuration: 0.04)
    static let dramaticCollapseSpring = Animation.spring(response: 0.48, dampingFraction: 0.6, blendDuration: 0.05)
}

struct FloatingMemoryHUDOverlay: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let containerSize: CGSize
    
    @Namespace private var hudNamespace
    @State private var cardIsExpanded = false
    @State private var storedCenter: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var compactMetrics = HUDCompactMetrics()
    @State private var hasBeenDragged = false
    @State private var currentAnchor: HorizontalAnchor = .right
    private let verticalMargin: CGFloat = 0
    private var expandedHeight: CGFloat { FloatingHUDConstants.expandedHeight }
    private var maxExpandedWidth: CGFloat { FloatingHUDConstants.expandedWidthMax }
    private var horizontalMargin: CGFloat { FloatingHUDConstants.horizontalMargin }
    private var expansionAnimation: Animation { FloatingHUDConstants.expansionAnimation }
    private var attachmentAnimation: Animation { FloatingHUDConstants.attachmentAnimation }
    
    var body: some View {
        let baseResolvedSize = resolvedCardSize(in: containerSize, expanded: cardIsExpanded)
        let compactWidth = max(compactMetrics.intrinsicWidth, compactMetrics.minimumWidth)
        let collapsedWidth = compactWidth > 0 ? min(compactWidth, baseResolvedSize.width) : baseResolvedSize.width
        let displayedWidth = cardIsExpanded ? baseResolvedSize.width : collapsedWidth
        let cardSize = CGSize(width: displayedWidth, height: baseResolvedSize.height)
        let baseCenter = storedCenter ?? defaultCenter(for: cardSize, in: containerSize)
        let clampedCenter = snapCenter(baseCenter, cardSize: cardSize, in: containerSize, anchorOverride: nil)
        let dragAdjustedCenter = CGPoint(
            x: clampedCenter.x + dragOffset.width,
            y: clampedCenter.y + dragOffset.height
        )
        
        FlexibleMemoryHUDView(
            monitor: monitor,
            isExpanded: cardIsExpanded,
            targetSize: cardSize,
            compactMetrics: $compactMetrics,
            namespace: hudNamespace
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let nextExpanded = !cardIsExpanded
            let nextSize = resolvedCardSize(in: containerSize, expanded: nextExpanded)
        let referencePoint = storedCenter ?? defaultCenter(for: nextSize, in: containerSize)
        let anchor = hasBeenDragged ? currentAnchor : .right
        let nextCenter = snapCenter(referencePoint, cardSize: nextSize, in: containerSize, anchorOverride: anchor)
            withAnimation(FloatingHUDConstants.dramaticCollapseSpring) {
                storedCenter = nextCenter
                cardIsExpanded = nextExpanded
            }
        }
        .frame(
            width: displayedWidth,
            height: cardSize.height,
            alignment: cardIsExpanded ? .topLeading : .topTrailing
        )
        .position(dragAdjustedCenter)
        .animation(FloatingHUDConstants.dramaticCollapseSpring, value: cardIsExpanded)
        .highPriorityGesture(dragGesture(cardSize: cardSize, origin: clampedCenter))
        .onAppear {
            storedCenter = clampedCenter
            currentAnchor = .right
        }
        .onChange(of: compactMetrics.labelSize) { _ in
            guard !cardIsExpanded, !hasBeenDragged else { return }
            let nextCard = resolvedCardSize(in: containerSize, expanded: false)
            storedCenter = snapCenter(defaultCenter(for: nextCard, in: containerSize), cardSize: nextCard, in: containerSize, anchorOverride: .right)
        }
        .onChange(of: containerSize) { newValue in
            let nextCard = resolvedCardSize(in: newValue, expanded: cardIsExpanded)
            let reference = hasBeenDragged ? (storedCenter ?? defaultCenter(for: nextCard, in: newValue)) : defaultCenter(for: nextCard, in: newValue)
            withAnimation(attachmentAnimation) {
                let anchor = hasBeenDragged ? currentAnchor : .right
                storedCenter = snapCenter(reference, cardSize: nextCard, in: newValue, anchorOverride: anchor)
            }
        }
        .onChange(of: cardIsExpanded) { newValue in
            let nextCard = resolvedCardSize(in: containerSize, expanded: newValue)
            withAnimation(expansionAnimation) {
                storedCenter = snapCenter(storedCenter ?? defaultCenter(for: nextCard, in: containerSize), cardSize: nextCard, in: containerSize, anchorOverride: currentAnchor)
            }
        }
    }
    
    private func dragGesture(cardSize: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
                hasBeenDragged = true
            }
            .onEnded { value in
                let finalCenter = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                withAnimation(attachmentAnimation) {
                    let snapped = snapCenter(finalCenter, cardSize: cardSize, in: containerSize, anchorOverride: nil)
                    storedCenter = snapped
                    dragOffset = .zero
                    currentAnchor = snapped.x >= containerSize.width / 2 ? .right : .left
                    if isDockedToDefault(cardSize: cardSize) {
                        hasBeenDragged = false
                    }
                }
            }
    }
    
    private func resolvedCardSize(in container: CGSize, expanded: Bool) -> CGSize {
        if expanded {
            let compactWidth = resolvedCompactWidth(in: container)
            let availableWidth = max(container.width - (horizontalMargin * 2), compactWidth)
            let width = min(availableWidth, maxExpandedWidth)
            return CGSize(width: width, height: expandedHeight)
        } else {
            return CGSize(width: resolvedCompactWidth(in: container), height: resolvedCompactHeight)
        }
    }
    
    private func defaultCenter(for cardSize: CGSize, in container: CGSize) -> CGPoint {
        CGPoint(
            x: container.width - cardSize.width / 2 - horizontalMargin,
            y: container.height - cardSize.height / 2 - (verticalMargin * 2)
        )
    }
    
    private func snapCenter(_ point: CGPoint, cardSize: CGSize, in container: CGSize, anchorOverride: HorizontalAnchor?) -> CGPoint {
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        let minY = halfHeight + verticalMargin
        let maxY = max(container.height - halfHeight - verticalMargin, minY)
        let anchor: HorizontalAnchor = anchorOverride ?? (point.x >= container.width / 2 ? .right : .left)
        let anchoredX = anchoredXPosition(for: anchor, cardSize: cardSize, in: container)
        let clampedY = min(max(point.y, minY), maxY)
        return CGPoint(
            x: anchoredX,
            y: clampedY
        )
    }
    
    private func anchoredXPosition(for anchor: HorizontalAnchor, cardSize: CGSize, in container: CGSize) -> CGFloat {
        let halfWidth = cardSize.width / 2
        let minX = halfWidth + horizontalMargin
        let maxX = max(container.width - halfWidth - horizontalMargin, minX)
        switch anchor {
        case .left:
            return minX
        case .right:
            return maxX
        }
    }

    private func isDockedToDefault(cardSize: CGSize) -> Bool {
        guard let storedCenter else { return true }
        let defaultPoint = defaultCenter(for: cardSize, in: containerSize)
        return abs(storedCenter.x - defaultPoint.x) < 1.0 && abs(storedCenter.y - defaultPoint.y) < 1.0
    }
    
}

private enum HorizontalAnchor {
    case left
    case right
}

private struct FlexibleMemoryHUDView: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let isExpanded: Bool
    let targetSize: CGSize
    @Binding var compactMetrics: HUDCompactMetrics
    let namespace: Namespace.ID
    
    var body: some View {
        let cornerRadius: CGFloat = isExpanded ? 28 : 18
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let stackAlignment: Alignment = isExpanded ? .topLeading : .topTrailing
        
        ZStack(alignment: stackAlignment) {
            if isExpanded {
                expandedContent
            } else {
                compactContentView(isProxy: false)
            }
        }
        .animation(FloatingHUDConstants.dramaticCollapseSpring, value: isExpanded)
        .frame(
            width: isExpanded ? targetSize.width : nil,
            height: isExpanded ? targetSize.height : nil,
            alignment: stackAlignment
        )
        .liquidGlassTile(tint: .cyan.opacity(isExpanded ? 0.85 : 0.75), shape: shape)
        .shadow(color: Color.black.opacity(isExpanded ? 0.25 : 0.18), radius: isExpanded ? 22 : 14, x: 0, y: isExpanded ? 16 : 10)
        .foregroundStyle(.primary)
        .onPreferenceChange(CompactContentSizePreferenceKey.self) { newSize in
            updateCompactContentSize(newSize)
        }
        .onPreferenceChange(CompactLabelSizePreferenceKey.self) { newSize in
            updateCompactLabelSize(newSize)
        }
    }
    
    private func compactContentView(isProxy: Bool) -> some View {
        HStack(alignment: .center, spacing: FloatingHUDConstants.compactSpacing + 2) {
            memoryIcon(expanded: false, isProxy: isProxy)
            compactValueStack(applyMatchedEffects: !isProxy)
        }
        .padding(.horizontal, FloatingHUDConstants.compactHorizontalPadding)
        .padding(.vertical, FloatingHUDConstants.compactVerticalPadding)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .allowsHitTesting(false)
                    .preference(key: CompactContentSizePreferenceKey.self, value: proxy.size)
            }
        )
    }
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                memoryIcon(expanded: true)
                expandedValueStack
                Spacer(minLength: 0)
            }

            Divider().blendMode(.overlay)
            
            MemoryUsageGraphView(samples: monitor.samples)
                .frame(height: max(targetSize.height - 140, 120))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
    
    private var compactDisplayText: String {
        guard let value = monitor.currentMegabytes else { return "-- MB" }
        return String(format: "%.0f MB", value)
    }
    
    private var expandedValueText: String {
        guard let value = monitor.currentMegabytes else { return "-- MB" }
        return String(format: "%.1f MB", value)
    }
    
    private func memoryIcon(expanded: Bool, isProxy: Bool = false) -> some View {
        let icon = Image(systemName: "memorychip")
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: expanded ? 32 : FloatingHUDConstants.compactIconSize, height: expanded ? 32 : FloatingHUDConstants.compactIconSize)
            .padding(expanded ? 10 : FloatingHUDConstants.compactIconPadding)
            .background(
                RoundedRectangle(cornerRadius: expanded ? 16 : 14, style: .continuous)
                    .fill(Color.white.opacity(expanded ? 0.1 : 0.12))
            )
        if isProxy {
            return AnyView(icon)
        } else {
            return AnyView(icon.matchedGeometryEffect(id: "hud-icon", in: namespace))
        }
    }
    
    private func compactValueStack(applyMatchedEffects: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(compactDisplayText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .fixedSize(horizontal: true, vertical: false)
                .conditionalMatchedGeometryEffect(id: "hud-value-number", in: namespace, isProxy: !applyMatchedEffects)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .allowsHitTesting(false)
                    .preference(key: CompactLabelSizePreferenceKey.self, value: proxy.size)
            }
        )
        .overlay(alignment: .bottomLeading) {
            Text("Current memory usage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .opacity(0.001)
                .conditionalMatchedGeometryEffect(id: "hud-value-caption", in: namespace, isProxy: !applyMatchedEffects)
        }
        .conditionalMatchedGeometryEffect(id: "hud-value-stack", in: namespace, isProxy: !applyMatchedEffects)
    }
    
    private var expandedValueStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(expandedValueText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
                .matchedGeometryEffect(id: "hud-value-number", in: namespace)
            Text("Current memory usage")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .matchedGeometryEffect(id: "hud-value-caption", in: namespace)
        }
        .matchedGeometryEffect(id: "hud-value-stack", in: namespace)
    }
    
    private func updateCompactLabelSize(_ newSize: CGSize) {
        var metrics = compactMetrics
        guard metrics.updateLabelSizeIfNeeded(newSize) else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            compactMetrics = metrics
        }
    }
    
    private func updateCompactContentSize(_ newSize: CGSize) {
        var metrics = compactMetrics
        guard metrics.updateContentSizeIfNeeded(newSize) else { return }
        #if DEBUG
        print("HUD compact content size updated:", newSize)
        #endif
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            compactMetrics = metrics
        }
    }
}

private struct CompactLabelSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct CompactContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}


private struct HUDCompactMetrics: Equatable {
    var labelSize: CGSize = CGSize(width: 80, height: 24)
    var contentSize: CGSize = .zero
    
    var minimumWidth: CGFloat {
        iconBlockWidth + (FloatingHUDConstants.compactHorizontalPadding * 2)
    }
    
    var intrinsicWidth: CGFloat {
        if contentSize.width > 0 {
            return contentSize.width
        }
        return fallbackWidthFromLabel
    }
    
    var intrinsicHeight: CGFloat {
        if contentSize.height > 0 {
            return contentSize.height
        }
        return fallbackHeightFromLabel
    }
    
    mutating func updateLabelSizeIfNeeded(_ newSize: CGSize) -> Bool {
        guard newSize.width > 0, newSize.height > 0 else { return false }
        let delta = abs(newSize.width - labelSize.width) + abs(newSize.height - labelSize.height)
        guard delta > 0.5 else { return false }
        labelSize = newSize
        return true
    }
    
    mutating func updateContentSizeIfNeeded(_ newSize: CGSize) -> Bool {
        guard newSize.width > 0, newSize.height > 0 else { return false }
        let delta = abs(newSize.width - contentSize.width) + abs(newSize.height - contentSize.height)
        guard delta > 0.5 else { return false }
        contentSize = newSize
        return true
    }
    
    private var fallbackWidthFromLabel: CGFloat {
        guard labelSize.width > 0 else { return minimumWidth }
        return iconBlockWidth
            + FloatingHUDConstants.compactSpacing
            + labelSize.width
            + (FloatingHUDConstants.compactHorizontalPadding * 2)
    }
    
    private var fallbackHeightFromLabel: CGFloat {
        let measuredHeight = labelSize.height > 0 ? labelSize.height : iconBlockHeight
        let contentHeight = max(iconBlockHeight, measuredHeight)
        return contentHeight + (FloatingHUDConstants.compactVerticalPadding * 2)
    }
    
    private var iconBlockWidth: CGFloat {
        FloatingHUDConstants.compactIconSize + (FloatingHUDConstants.compactIconPadding * 2)
    }
    
    private var iconBlockHeight: CGFloat {
        FloatingHUDConstants.compactIconSize + (FloatingHUDConstants.compactIconPadding * 2)
    }
}

private extension View {
    func conditionalMatchedGeometryEffect(id: String, in namespace: Namespace.ID, isProxy: Bool) -> some View {
        if isProxy {
            return AnyView(self)
        } else {
            return AnyView(self.matchedGeometryEffect(id: id, in: namespace))
        }
    }
}

private extension FloatingMemoryHUDOverlay {
    func resolvedCompactWidth(in container: CGSize) -> CGFloat {
        let measured = max(compactMetrics.intrinsicWidth, compactMetrics.minimumWidth)
        let available = max(container.width - (horizontalMargin * 2), compactMetrics.minimumWidth)
        return min(measured, available)
    }
    
    var resolvedCompactHeight: CGFloat {
        compactMetrics.intrinsicHeight
    }
}
