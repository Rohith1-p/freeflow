import SwiftUI

/// Premium glass styling: real Liquid Glass on macOS 26+, frosted material
/// fallback on macOS 14/15.
extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    func glassSidebar() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.ultraThinMaterial)
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(Capsule().fill(.ultraThinMaterial))
        }
    }
}
