import SwiftUI

struct GlassCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(24)
        .modifier(AdaptiveGlass())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdaptiveGlass<S: Shape>: ViewModifier {
    var shape: S

    init(shape: S = RoundedRectangle(cornerRadius: 30, style: .continuous)) {
        self.shape = shape
    }

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(ShapeView(shape: shape).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private struct ShapeView<S: Shape>: Shape {
    var shape: S

    func path(in rect: CGRect) -> Path {
        shape.path(in: rect)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color
    var labelColor: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .foregroundStyle(labelColor)
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .colorMultiply(tint.opacity(0.3).opacity(0.25))
            )
            .overlay(
                shape
                    .stroke(tint.opacity(0.5), lineWidth: 1.1)
            )
            .shadow(color: tint.opacity(0.3), radius: 8, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AccentGlass<S: Shape>: ViewModifier {
    let accent: Color
    var shape: S

    init(accent: Color, shape: S = RoundedRectangle(cornerRadius: 18, style: .continuous)) {
        self.accent = accent
        self.shape = shape
    }

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .colorMultiply(accent.opacity(0.3))
            )
            .overlay(
                shape
                    .stroke(accent.opacity(0.3), lineWidth: 1.2)
            )
            .shadow(color: accent.opacity(0.3), radius: 10, x: 0, y: 6)
    }
}

extension View {
    func accentGlass(_ color: Color, shape: some Shape = RoundedRectangle(cornerRadius: 18, style: .continuous)) -> some View {
        modifier(AccentGlass(accent: color, shape: shape))
    }
}
