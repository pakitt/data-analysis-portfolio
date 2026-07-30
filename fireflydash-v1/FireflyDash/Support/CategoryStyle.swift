import SwiftUI

/// A stable colour + SF Symbol per category, keyed on the *main* category so the
/// same category looks identical in every view (donut, Sankey, tables, lists).
/// Known categories get a curated icon/colour; anything else falls back to a
/// deterministic hash so it's still consistent run-to-run.
enum CategoryStyle {
    /// keyword(s) found in the main category → SF Symbol + colour.
    /// "personal care" is listed first so it wins before the auto/"car" entry.
    private static let table: [(keys: [String], icon: String, color: Color)] = [
        (["personal care", "barber", "beauty", "hair", "cosmetic", "grooming", "salon"], "scissors", Color(red: 0.6, green: 0.4, blue: 0.2)),
        // Cashback before cash (so "cashback" doesn't match "cash"); both before the bank/fees entry.
        (["cashback", "cash back"], "creditcard.fill", Color(red: 0.2, green: 0.6, blue: 0.55)),
        (["cash"], "banknote.fill", Color(red: 0.3, green: 0.55, blue: 0.4)),
        (["withdrawal", "atm"], "building.columns.fill", Color(red: 0.42, green: 0.45, blue: 0.5)),
        // Public transport before "auto" (which owns the "transport" keyword).
        (["public transport", "bus", "metro", "tram", "subway", "rail", "commute", "transit"], "bus.fill", Color(red: 0.2, green: 0.5, blue: 0.7)),
        // Tax before fees (which also lists "tax"); a paperwork icon for bureaucracy.
        (["tax", "vat", "hmrc", "irs", "duty"], "doc.text.fill", Color(red: 0.5, green: 0.45, blue: 0.55)),
        (["home", "rent", "mortgage", "house", "household", "furnish", "appliance", "improvement", "supplies"], "house.fill", .blue),
        (["food", "restaurant", "grocer", "dining", "eating", "cafe", "coffee", "meal", "lunch", "takeaway"], "fork.knife", .orange),
        (["health", "pharmac", "medical", "doctor", "dental", "clinic"], "cross.case.fill", .red),
        (["auto", "car", "fuel", "vehicle", "transport", "parking", "taxi"], "car.fill", .teal),
        (["utilit", "electric", "gas", "water", "internet", "phone", "mobile", "heating"], "bolt.fill", .yellow),
        (["travel", "flight", "hotel", "holiday", "vacation", "trip"], "airplane", .indigo),
        (["shop", "cloth", "amazon", "retail"], "bag.fill", .pink),
        (["entertain", "movie", "cinema", "game", "gaming", "music", "hobby", "sport"], "theatermasks.fill", .purple),
        (["train", "educat", "course", "learning", "school", "study"], "graduationcap.fill", .mint),
        (["subscri", "streaming", "netflix"], "arrow.triangle.2.circlepath", .cyan),
        (["fee", "charge", "bank", "tax", "interest"], "banknote.fill", Color(red: 0.42, green: 0.45, blue: 0.5)),
        (["insurance"], "shield.fill", Color(red: 0.35, green: 0.55, blue: 0.2)),
        (["pet", "dog", "cat"], "pawprint.fill", Color(red: 0.55, green: 0.35, blue: 0.15)),
        (["gift", "present", "donation", "charity"], "gift.fill", Color(red: 0.85, green: 0.2, blue: 0.5)),
        (["kid", "child", "baby", "family"], "teddybear.fill", Color(red: 0.9, green: 0.6, blue: 0.2)),
        (["saving"], "dollarsign.circle.fill", Color(red: 0.95, green: 0.5, blue: 0.6)),
        (["income", "salary", "paycheck", "wage"], "dollarsign.circle.fill", .green),
    ]

    /// Whole-word match for short keywords (so "car" doesn't match "care"),
    /// substring for longer ones (so "utilit" matches "utilities").
    private static func matches(_ main: String, _ key: String) -> Bool {
        if key.contains(" ") { return main.contains(key) }
        let words = main.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(key) { return true }
        return key.count >= 4 && main.contains(key)
    }

    private static func styled(_ category: String) -> (icon: String, color: Color) {
        let main = Insights.splitCategory(category).main.lowercased()
        if main.isEmpty || main.hasPrefix("uncategor") { return ("tag.fill", .gray) }
        if main == "other" || main.hasPrefix("other ") { return ("shippingbox.fill", .gray) }
        for entry in table where entry.keys.contains(where: { matches(main, $0) }) {
            return (entry.icon, entry.color)
        }
        // Deterministic fallback (djb2) so unknown categories stay consistent.
        var hash = 5381
        for byte in main.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return ("tag.fill", Palette.colors[abs(hash) % Palette.colors.count])
    }

    static func icon(_ category: String) -> String { styled(category).icon }
    static func color(_ category: String) -> Color { styled(category).color }
}

/// The category's SF Symbol, tinted in its colour on a legible faint tint of the
/// same colour.
struct CategoryBadge: View {
    @Environment(\.interfaceScale) private var scale
    let category: String
    var size: CGFloat = 22

    var body: some View {
        let scaledSize = size * scale
        Image(systemName: CategoryStyle.icon(category))
            .font(.system(size: scaledSize * 0.52, weight: .semibold))
            .foregroundStyle(CategoryStyle.color(category))
            .frame(width: scaledSize, height: scaledSize)
            .background(CategoryStyle.color(category).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: scaledSize * 0.3))
    }
}

extension View {
    /// Cap content to a comfortable reading width and centre it, so tables and
    /// lists don't sprawl edge-to-edge (leaving huge gaps between the left-hand
    /// labels and the right-aligned numbers) on very wide windows.
    func readableWidth(_ maxWidth: CGFloat = 960) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
