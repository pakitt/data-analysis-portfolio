import SwiftUI
import SwiftData

/// Tag tracker: every Firefly tag with its transaction count, total spend, and
/// active period — for following projects/events that cut across categories
/// (a renovation, a trip, a tax year). Always all-time; click a tag to list its
/// transactions.
///
/// Uses the real (as-paid) transactions, never amortised slivers: a tag tracker
/// is about actual tagged entries, and slivers would multiply the counts.
struct TagsView: View {
    @Query private var allTransactions: [FFTransaction]
    @State private var sortOrder = [KeyPathComparator(\TagRow.spent, order: .reverse)]
    @State private var selection: TagRow.ID?
    @AppStorage("tagsSplitHeight") private var splitHeight = 0.0

    private var visible: [FFTransaction] { Insights.visible(allTransactions) }
    private var currency: String { Insights.baseCurrency(visible) }

    struct TagRow: Identifiable {
        var id: String { tag }
        let tag: String
        let count: Int
        let spent: Decimal      // total expenses, base currency
        let spentMixed: Bool
        let first: Date
        let last: Date

        /// "Mar 2024 – Jun 2026", or a single month when it's all one month.
        var period: String {
            let f = Date.FormatStyle.dateTime.month(.abbreviated).year()
            let a = first.formatted(f), b = last.formatted(f)
            return a == b ? a : "\(a) – \(b)"
        }
    }

    private var rows: [TagRow] {
        let conv = Insights.converter(for: visible)
        struct Acc { var count = 0; var spent: Decimal = 0; var spentMixed = false
                     var first: Date; var last: Date }
        var acc: [String: Acc] = [:]

        for t in visible where !t.tags.isEmpty {
            let (v, converted) = conv.value(t)
            for tag in t.tags {
                var e = acc[tag] ?? Acc(first: t.date, last: t.date)
                e.count += 1
                if t.isExpense {
                    e.spent += v
                    if converted { e.spentMixed = true }
                }
                e.first = min(e.first, t.date)
                e.last = max(e.last, t.date)
                acc[tag] = e
            }
        }

        return acc.map { tag, e in
            TagRow(tag: tag, count: e.count, spent: e.spent,
                   spentMixed: e.spentMixed, first: e.first, last: e.last)
        }
        .sorted(using: sortOrder)
    }

    /// Distinct tagged transactions (for the header count).
    private var taggedCount: Int {
        visible.reduce(0) { $0 + ($1.tags.isEmpty ? 0 : 1) }
    }

    private var subtitle: String {
        let tags = rows.count
        return "\(tags) tag\(tags == 1 ? "" : "s") · \(taggedCount) tagged transaction\(taggedCount == 1 ? "" : "s")"
    }

    /// Transactions behind the selected tag (newest first via TransactionPane).
    private var selectedTransactions: [FFTransaction] {
        guard let sel = selection else { return [] }
        return visible.filter { $0.tags.contains(sel) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(subtitle)
                .appFont(.title3, weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableWidth()
                .padding(.top, 16)
                .padding(.bottom, 12)
            if rows.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Tag transactions in Firefly (e.g. a trip or renovation) and they'll be tracked here. Press ⌘R to sync."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let fitContent = 28.0 + Double(rows.count) * 25 + 12
                    let maxTop = max(geo.size.height - 150, 120)
                    let topHeight = min(max(splitHeight > 0 ? splitHeight : fitContent, 120), maxTop)
                    VStack(spacing: 0) {
                        tagsTable
                            .frame(height: topHeight)
                        PaneDivider(current: topHeight, range: 120...maxTop) { splitHeight = $0 }
                        transactionsPane
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Tags")
    }

    private var tagsTable: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Tag", value: \.tag) { row in
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Palette.color(abs(djb2(row.tag))))
                    Text(row.tag)
                }
            }
            .width(min: 160, ideal: 260, max: 420)
            TableColumn("Txns", value: \.count) { row in
                Text("\(row.count)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(70)
            TableColumn("Spent", value: \.spent) { row in
                Text(row.spent.currency(currency, approx: row.spentMixed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(130)
            TableColumn("Period", value: \.last) { row in
                Text(row.period)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(180)
        }
        .tint(.blue)
        .readableWidth()
    }

    @ViewBuilder
    private var transactionsPane: some View {
        if let selection {
            TransactionPane(title: "#\(selection)",
                            transactions: selectedTransactions,
                            currency: currency)
        } else {
            ContentUnavailableView("Select a tag",
                                   systemImage: "list.bullet.rectangle",
                                   description: Text("Click a tag above to see all of its transactions."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Stable hash so a tag keeps the same colour between launches.
    private func djb2(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33) &+ Int(b) }
        return h
    }
}
