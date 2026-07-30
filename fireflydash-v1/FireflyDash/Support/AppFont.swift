import SwiftUI
import AppKit

/// macOS 26 (Tahoe) does have a system-level "Text Size" accessibility
/// setting (System Settings → Accessibility → Display), but per Apple's own
/// current documentation of it, it only works with a small allowlist of
/// first-party apps (Calendar, Finder, Mail, Messages, Notes) — there's no
/// published API for a third-party app to opt in, and `UIFontMetrics` (what
/// would drive custom-size scaling from it) isn't available on macOS at all.
/// `Font.system(.headline)` etc. and the `\.dynamicTypeSize` environment key
/// compile fine but do nothing here — confirmed empirically (a debug build
/// with an on-screen readout showed the environment value was received
/// correctly, but plain semantic-style Font sizes never moved). So there's
/// no first-party way for FireflyDash to hook into anything OS-driven; this
/// file is a deliberate, self-contained substitute for the window-width
/// scaling this app wants (not a general Dynamic Type shim) that may be
/// worth revisiting if a future macOS release opens up the Text Size API.
///
/// `.appFont(_:)` below is a drop-in replacement for `.appFont(.headline)` /
/// `.appFont(.title3, weight: .semibold)` etc. that resolves to the SAME macOS
/// point sizes at 1.0 scale (offsets from `NSFont.systemFontSize`, mirroring
/// macOS's own semantic text styles), but actually grows when
/// `\.interfaceScale` does. Sizes are computed and handed to
/// `Font.system(size:)` — real glyph layout at the target size, not a
/// post-hoc `.scaleEffect` stretch, so text stays crisp instead of blurry.
/// `.scaledFrame(_:)` extends the same factor to a handful of the most
/// visible fixed-size icons/rings, so growth doesn't read as text-only.
private struct InterfaceScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// How much larger the app's text should render, derived from the
    /// window's width (set once, near the root, in ContentView). 1.0 at a
    /// normal window size, growing on a big/high-res display.
    var interfaceScale: CGFloat {
        get { self[InterfaceScaleKey.self] }
        set { self[InterfaceScaleKey.self] = newValue }
    }
}

extension Font.TextStyle {
    /// This style's point size at 1.0 scale, as an offset from
    /// `NSFont.systemFontSize` (13pt by default on macOS) — the same
    /// relative offsets macOS's own text styles use.
    fileprivate var macBaseSize: CGFloat {
        let base = NSFont.systemFontSize
        switch self {
        case .largeTitle: return base + 17
        case .title: return base + 11
        case .title2: return base + 5
        case .title3: return base + 3
        case .headline, .body: return base
        case .callout: return base - 1
        case .subheadline: return base - 2
        case .footnote: return base - 4
        case .caption: return base - 5
        case .caption2: return base - 6
        @unknown default: return base
        }
    }

    /// Matches macOS: every style is regular weight except headline, which
    /// is semibold — same as `Font.headline`/`.appFont(.headline)`.
    fileprivate var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.interfaceScale) private var scale
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: style.macBaseSize * scale,
                              weight: weight ?? style.defaultWeight,
                              design: design))
    }
}

extension View {
    /// Drop-in for `.appFont(.headline)`, `.appFont(.title3, weight: .semibold)`
    /// etc. that actually scales with the window — see `AppFont.swift`'s
    /// header comment for why plain `.appFont(.headline)` doesn't on macOS.
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(style: style, weight: weight, design: design))
    }

    /// Drop-in for an explicit `.font(.system(size:weight:design:))` call
    /// (the Dashboard hero numbers, piggy-ring labels) that scales the same
    /// way as `.appFont(_:)` instead of staying pinned at a fixed point size.
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontSizeModifier(size: size, weight: weight, design: design))
    }
}

private struct AppFontSizeModifier: ViewModifier {
    @Environment(\.interfaceScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// A fixed `width == height` frame (an icon badge, a progress ring) that
    /// scales with `\.interfaceScale` instead of staying pinned at `size`
    /// regardless of window width.
    func scaledFrame(_ size: CGFloat) -> some View {
        modifier(ScaledFrameModifier(size: size))
    }
}

private struct ScaledFrameModifier: ViewModifier {
    @Environment(\.interfaceScale) private var scale
    let size: CGFloat

    func body(content: Content) -> some View {
        content.frame(width: size * scale, height: size * scale)
    }
}
