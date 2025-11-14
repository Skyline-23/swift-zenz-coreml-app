import SwiftUI
import Charts

struct FloatingMemoryHUDOverlay: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let containerSize: CGSize
    
    @State private var isExpanded = false
    @State private var storedCenter: CGPoint? = nil
    @State private var dragOffset: CGSize = .zero
    
    private let compactDiameter: CGFloat = 70
    private let expandedHeight: CGFloat = 260
    private let maxExpandedWidth: CGFloat = 360
    private let margin: CGFloat = 16
    private let toggleAnimation = Animation.spring(response: 0.3, dampingFraction: 0.78)
    
    var body: some View {
        let cardSize = resolvedCardSize(in: containerSize, expanded: isExpanded)
        let baseCenter = storedCenter ?? defaultCenter(for: cardSize, in: containerSize)
        let clampedCenter = clampCenter(baseCenter, cardSize: cardSize, in: containerSize)
        let dragAdjustedCenter = CGPoint(
            x: clampedCenter.x + dragOffset.width,
            y: clampedCenter.y + dragOffset.height
        )
        
        Button {
            withAnimation(toggleAnimation) {
                isExpanded.toggle()
            }
        } label: {
            FlexibleMemoryHUDView(
                monitor: monitor,
                isExpanded: isExpanded,
                targetSize: cardSize
            )
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
            storedCenter = clampCenter(storedCenter ?? defaultCenter(for: nextCard, in: newValue), cardSize: nextCard, in: newValue)
        }
        .onChange(of: isExpanded) { newValue in
            let nextCard = resolvedCardSize(in: containerSize, expanded: newValue)
            storedCenter = clampCenter(storedCenter ?? defaultCenter(for: nextCard, in: containerSize), cardSize: nextCard, in: containerSize)
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
                storedCenter = clampCenter(finalCenter, cardSize: cardSize, in: containerSize)
                dragOffset = .zero
            }
    }
    
    private func resolvedCardSize(in container: CGSize, expanded: Bool) -> CGSize {
        if expanded {
            let width = min(max(container.width - (margin * 2), compactDiameter), maxExpandedWidth)
            return CGSize(width: width, height: expandedHeight)
        } else {
            return CGSize(width: compactDiameter, height: compactDiameter)
        }
    }
    
    private func defaultCenter(for cardSize: CGSize, in container: CGSize) -> CGPoint {
        CGPoint(
            x: container.width - cardSize.width / 2 - margin,
            y: container.height - cardSize.height / 2 - (margin * 2)
        )
    }
    
    private func clampCenter(_ point: CGPoint, cardSize: CGSize, in container: CGSize) -> CGPoint {
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        let minX = halfWidth + margin
        let maxX = max(container.width - halfWidth - margin, minX)
        let minY = halfHeight + margin
        let maxY = max(container.height - halfHeight - margin, minY)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }
    
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
        VStack(spacing: 8) {
            Image(systemName: "memorychip")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(compactValueText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("MB")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
