import Foundation

/// Namespacing for settings that reference the *contents* of the active store —
/// selected savings/funding accounts, excluded categories, base currency and
/// paycheck rules. Sample (demo) mode and real mode keep fully separate copies
/// of these, so switching datasets never cross-contaminates choices made against
/// account IDs or category names that only exist in one of them.
///
/// Connection settings (server URL, token, trust) and pure-UI preferences
/// (section order, ranges, thresholds) are NOT namespaced — they're shared.
enum AppSettings {
    static var sampleMode: Bool { UserDefaults.standard.bool(forKey: "useSampleData") }

    /// The dataset-scoped key for `base`: prefixed with "sample." in demo mode.
    static func key(_ base: String) -> String { sampleMode ? "sample.\(base)" : base }
}
