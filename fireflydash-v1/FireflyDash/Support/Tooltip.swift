import SwiftUI

/// Pure-SwiftUI tooltip. `.help()` is SwiftUI's only built-in tooltip and it
/// never fires inside List/Table rows on macOS, so instead we present a
/// popover after the standard hover delay and dismiss it when the pointer
/// leaves the view.
private struct HoverTooltip: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        if hovering { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text)
                    .appFont(.callout)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    // Without this the popover measures the text as a single
                    // line and clips everything after the first one.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400, alignment: .leading)
                    .padding(12)
            }
    }
}

extension View {
    /// Attach a hover tooltip that also works inside List/Table rows.
    func tooltip(_ text: String) -> some View {
        modifier(HoverTooltip(text: text))
    }

    /// Optional variant: nil leaves the view untouched.
    @ViewBuilder
    func tooltip(_ text: String?) -> some View {
        if let text {
            modifier(HoverTooltip(text: text))
        } else {
            self
        }
    }
}
