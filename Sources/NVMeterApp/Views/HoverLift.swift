import SwiftUI
import AppKit

/// Lifts a card on hover: subtle rise + shadow + pointing-hand cursor.
/// Signals "this is clickable" in a popover full of otherwise-static cards.
struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.012 : 1.0)
            .offset(y: hovering ? -1 : 0)
            .shadow(
                color: .black.opacity(hovering ? 0.18 : 0),
                radius: hovering ? 7 : 0,
                y: hovering ? 3 : 0
            )
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}
