import SwiftUI
import Charts

private enum FloatingHUDConstants {
    static let compactWidth: CGFloat = 140
    static let compactHeight: CGFloat = 60
    static let expandedHeight: CGFloat = 260
    static let expandedWidthMax: CGFloat = 360
    static let horizontalMargin: CGFloat = 8
    static let toggleAnimation = Animation.spring(response: 0.3, dampingFraction: 0.78)
}

struct FloatingMemoryHUDOverlay: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let containerSize: CGSize
    
    @State private var isExpanded = false
    @State private var storedCenter: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    
    private let verticalMargin: CGFloat = 0
    private var compactWidth: CGFloat { FloatingHUDConstants.compactWidth }
    private var compactHeight: CGFloat { FloatingHUDConstants.compactHeight }
    private var expandedHeight: CGFloat { FloatingHUDConstants.expandedHeight }
    private var maxExpandedWidth: CGFloat { FloatingHUDConstants.expandedWidthMax }
    private var horizontalMargin: CGFloat { FloatingHUDConstants.horizontalMargin }
    private var toggleAnimation: Animation { FloatingHUDConstants.toggleAnimation }
    
    var body: some View {
        let cardSize = resolvedCardSize(in: containerSize, expanded: isExpanded)
        let baseCenter = storedCenter ?? defaultCenter(for: cardSize, in: containerSize)
        let clampedCenter = snapCenter(baseCenter, cardSize: cardSize, in: containerSize)
        let dragAdjustedCenter = CGPoint(
            x: clampedCenter.x + dragOffset.width,
            y: clampedCenter.y + dragOffset.height
        )
        
        FlexibleMemoryHUDView(
            monitor: monitor,
            isExpanded: isExpanded,
            targetSize: cardSize
        )
        .scaleEffect(isExpanded ? 1 : 0.9, anchor: .center)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(toggleAnimation) {
                isExpanded.toggle()
            }
        }
        .buttonStyle(.plain)
        .frame(width: cardSize.width, height: cardSize.height)
        .position(dragAdjustedCenter)
        .highPriorityGesture(dragGesture(cardSize: cardSize, origin: clampedCenter))
        .onAppear {
            storedCenter = clampedCenter
        }
        .onChange(of: containerSize) { newValue in
            let nextCard = resolvedCardSize(in: newValue, expanded: isExpanded)
            storedCenter = snapCenter(storedCenter ?? defaultCenter(for: nextCard, in: newValue), cardSize: nextCard, in: newValue)
        }
        .onChange(of: isExpanded) { newValue in
            let nextCard = resolvedCardSize(in: containerSize, expanded: newValue)
            storedCenter = snapCenter(storedCenter ?? defaultCenter(for: nextCard, in: containerSize), cardSize: nextCard, in: containerSize)
        }
    }
    
    private func dragGesture(cardSize: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let finalCenter = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                storedCenter = snapCenter(finalCenter, cardSize: cardSize, in: containerSize)
                dragOffset = .zero
            }
    }
    
    private func resolvedCardSize(in container: CGSize, expanded: Bool) -> CGSize {
        if expanded {
            let width = min(max(container.width - (horizontalMargin * 2), compactWidth), maxExpandedWidth)
            return CGSize(width: width, height: expandedHeight)
        } else {
            return CGSize(width: compactWidth, height: compactHeight)
        }
    }
    
    private func defaultCenter(for cardSize: CGSize, in container: CGSize) -> CGPoint {
        CGPoint(
            x: container.width - cardSize.width / 2 - horizontalMargin,
            y: container.height - cardSize.height / 2 - (verticalMargin * 2)
        )
    }
    
    private func snapCenter(_ point: CGPoint, cardSize: CGSize, in container: CGSize) -> CGPoint {
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        let minY = halfHeight + verticalMargin
        let maxY = max(container.height - halfHeight - verticalMargin, minY)
        let anchor: HorizontalAnchor = point.x >= container.width / 2 ? .right : .left
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
    
}

private enum HorizontalAnchor {
    case left
    case right
}

private struct FlexibleMemoryHUDView: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let isExpanded: Bool
    let targetSize: CGSize
    
    var body: some View {
        let cornerRadius: CGFloat = isExpanded ? 28 : 18
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        Group {
            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .frame(width: targetSize.width, height: targetSize.height, alignment: .topLeading)
        .liquidGlassTile(tint: .cyan.opacity(isExpanded ? 0.85 : 0.75), shape: shape)
        .shadow(color: Color.black.opacity(isExpanded ? 0.25 : 0.18), radius: isExpanded ? 22 : 14, x: 0, y: isExpanded ? 16 : 10)
        .foregroundStyle(.primary)
    }
    
    private var compactContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "memorychip")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(compactValueText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("MB")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "memorychip")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(expandedValueText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Current memory usage")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            
            Divider().blendMode(.overlay)
            
            MemoryUsageChart(samples: monitor.samples)
                .frame(height: max(targetSize.height - 140, 120))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
    
    private var compactValueText: String {
        guard let value = monitor.currentMegabytes else { return "--" }
        return String(format: "%.0f", value)
    }
    
    private var expandedValueText: String {
        guard let value = monitor.currentMegabytes else { return "-- MB" }
        return String(format: "%.1f MB", value)
    }
}

private struct MemoryUsageChart: View {
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
                        y: .value("Memory", sample.megabytes)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.cyan)
                    .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    
                    AreaMark(
                        x: .value("Timestamp", sample.timestamp),
                        y: .value("Memory", sample.megabytes)
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
