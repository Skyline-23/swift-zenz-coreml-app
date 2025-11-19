import SwiftUI
import FloatingHUD

struct MemoryHUDOverlay: View {
    @ObservedObject var monitor: MemoryUsageMonitor
    let containerSize: CGSize
    let constants: FloatingHUDConstants
    let graphHeight: CGFloat
    
    init(
        monitor: MemoryUsageMonitor,
        containerSize: CGSize,
        constants: FloatingHUDConstants = .memoryDefault,
        graphHeight: CGFloat = 140
    ) {
        self.monitor = monitor
        self.containerSize = containerSize
        self.constants = constants
        self.graphHeight = graphHeight
    }
    
    var body: some View {
        return FloatingHUDOverlay(
            containerSize: containerSize,
            compact: { compactContent },
            expanded: { expandedContent },
            icon: { hudIcon },
            constants: constants
        )
    }
    
    private var hudIcon: some View {
        return Image(systemName: "memorychip")
            .font(.title3.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: constants.compact.iconSize, height: constants.compact.iconSize)
            .padding(constants.compact.iconPadding + 5) // subtle inset similar to prior style
    }
    
    private var compactContent: some View {
        return HStack(spacing: constants.compact.spacing) {
            Text(compactDisplayText)
                .monospacedDigit()
        }
        .padding(.horizontal, constants.compact.horizontalPadding)
        .padding(.vertical, constants.compact.verticalPadding)
    }
    
    private var expandedContent: some View {
        return VStack(alignment: .leading, spacing: 10) {
            descriptionLabel
            MemoryUsageGraphView(samples: monitor.samples)
                .frame(height: graphHeight)
                .padding(.top, 2)
        }
        .padding(.bottom, 10)
    }
    
    private var compactDisplayText: String {
        guard let value = monitor.currentMegabytes else { return "-- MB" }
        return String(format: "%.0f MB", value)
    }
    
    private var expandedValueText: String {
        guard let value = monitor.currentMegabytes else { return "-- MB" }
        return String(format: "%.1f MB", value)
    }
    
    private var descriptionLabel: some View {
        return Text("Current memory usage")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

extension FloatingHUDConstants {
    // Memory HUD defaults aligned with the sample: tight compact padding and a cyan liquid glass card style.
    static var memoryDefault: FloatingHUDConstants {
        let glassStyle = FloatingHUDCardStyle(
            compact: .init(
                background: { shape in
                    AnyView(
                        Color.clear
                            .liquidGlassTile(
                                tint: .cyan,
                                shape: shape
                            )
                    )
                },
                shadow: .init(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 10)
            ),
            expanded: .init(
                background: { shape in
                    AnyView(
                        Color.clear
                            .liquidGlassTile(
                                tint: .cyan,
                                shape: shape
                            )
                    )
                },
                shadow: .init(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)
            )
        )
        
        var constants = FloatingHUDConstants()
        constants.compact.iconSize = 20
        constants.compact.iconPadding = 1
        constants.compact.spacing = 0
        constants.compact.labelFont = .system(size: 18, weight: .semibold, design: .rounded)
        constants.compact.horizontalPadding = 8
        constants.compact.verticalPadding = 6
        constants.compact.cornerRadius = 18
        
        constants.expanded.headerSpacing = 0
        constants.expanded.horizontalPadding = 20
        constants.expanded.verticalPadding = 18
        constants.expanded.bodySpacing = 5
        constants.expanded.dividerSpacing = 0
        constants.expanded.showsDivider = true
        constants.expanded.dividerColor = nil
        constants.expanded.labelFont = .system(size: 35, weight: .semibold, design: .rounded)
        constants.expanded.cornerRadius = 28
        constants.expanded.widthMax = 360
        
        constants.layout.horizontalMargin = 8
        constants.layout.verticalMargin = 0
        
        constants.animations.expansion = .interactiveSpring(response: 0.27, dampingFraction: 0.7, blendDuration: 0.02)
        constants.animations.attachment = .interactiveSpring(response: 0.3, dampingFraction: 0.74, blendDuration: 0.04)
        constants.animations.dramaticCollapse = .spring(response: 0.48, dampingFraction: 0.6, blendDuration: 0.05)
        
        constants.cardStyle = glassStyle
        return constants
    }
}
