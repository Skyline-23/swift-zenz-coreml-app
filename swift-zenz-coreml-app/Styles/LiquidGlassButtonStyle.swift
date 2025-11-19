import SwiftUI

@available(iOS 26.0, *)
private struct LiquidGlassTileButtonStyle: ButtonStyle {
    let tint: Color
    let labelColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        
        return configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .foregroundStyle(labelColor)
            .glassEffect(
                .regular
                    .tint(tint.opacity(0.35))
            , in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct LegacyTintedGlassButtonStyle: ButtonStyle {
    let tint: Color
    let labelColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .foregroundStyle(labelColor)
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint.opacity(0.25)))
            )
            .overlay(shape.stroke(tint.opacity(0.45), lineWidth: 1.1))
            .shadow(color: tint.opacity(0.3), radius: 9, x: 0, y: 8)
    }
}

private struct TintedGlassButtonModifier: ViewModifier {
    let tint: Color
    let labelColor: Color
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .tint(labelColor)
                .buttonStyle(LiquidGlassTileButtonStyle(tint: tint, labelColor: labelColor))
        } else {
            content.buttonStyle(LegacyTintedGlassButtonStyle(tint: tint, labelColor: labelColor))
        }
    }
}

extension View {
    func tintedGlassButton(tint: Color, labelColor: Color) -> some View {
        modifier(TintedGlassButtonModifier(tint: tint, labelColor: labelColor))
    }
}

@available(iOS 26.0, *)
private struct ModernGlassTile<S: Shape>: ViewModifier {
    let tint: Color
    var shape: S
    
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint(tint.opacity(0.35)), in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .blendMode(.plusLighter)
            }
            .clipShape(shape)
            .contentShape(shape)
    }
}

private struct LegacyGlassTile<S: Shape>: ViewModifier {
    let tint: Color
    var shape: S
    
    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint.opacity(0.18)))
            )
            .overlay(shape.stroke(tint.opacity(0.35), lineWidth: 1))
            .shadow(color: tint.opacity(0.25), radius: 10, x: 0, y: 8)
            .clipShape(shape)
            .contentShape(shape)
    }
}

private struct LiquidGlassTileModifier<S: Shape>: ViewModifier {
    let tint: Color
    var shape: S
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.modifier(ModernGlassTile(tint: tint, shape: shape))
        } else {
            content.modifier(LegacyGlassTile(tint: tint, shape: shape))
        }
    }
}

extension View {
    func liquidGlassTile(
        tint: Color,
        shape: some Shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    ) -> some View {
        modifier(LiquidGlassTileModifier(tint: tint, shape: shape))
    }
}
