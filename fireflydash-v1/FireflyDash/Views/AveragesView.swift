import SwiftUI
import SwiftData
import Charts

/// Monthly spending averages per category over a selectable window of
/// complete past months (the current month is always excluded).
/// Tree mode groups "Main:Sub" categories under their main category.
struct AveragesView: View {
    @Query private var allTransactions: [FFTransaction]
    @State private var sortOrder = [KeyPathComparator(\Row.average, order: .reverse)]
    @State private var selection: Row.ID?
    @AppStorage("averagesRange") private var rangeRaw = FlowRange.threeMonths.rawValue
    /// Height of the top (averages) pane; 0 = never dragged, size to content.
    @AppStorage("averagesSplitHeight") private var splitHeight = 0.0
    /// Mirror of the dashboard's amortise toggle, so averages of lumpy bills
    /// (e.g. annual insurance tagged spread12) smooth out the same way.
    @AppStorage("amortizeView") private var amortizeView = false

    private var transactions: [FFTransaction] { Insights.visible(allTransactions) }
    /// Source for the averages themselves: amortised when the toggle is on.
    private var aggregated: [FFTransaction] { Insights.entries(allTransactions, amortize: amortizeView) }
    private var currency: String { Insights.baseCurrency(transactions) }

    /// Shares the dashboard's FlowRange vocabulary (minus Custom) so the range
    /// bars are consistent across views.
    private var range: FlowRange { FlowRange(rawValue: rangeRaw) ?? .threeMonths }

    struct Row: Identifiable {
        var id: String { category }
        let category: String   // full name; display label for tree children
        let label: String
        let average: Decimal   // average per complete month over the window
        let last30: Decimal    // spend in the rolling last 30 days
        let thisMonth: Decimal // spend so far in the current (in-progress) month
        // Each figure carries its OWN "involved a currency conversion" flag (shown
        // as ≈) — they're independent windows, so e.g. Last 30 days must not be
        // marked approximate just because some month in the averaging range was.
        let averageMixed: Bool
        let last30Mixed: Bool
        let thisMonthMixed: Bool
        var children: [Row]?

        /// Last 30 days vs the period average, as a signed fraction
        /// (+0.2 = 20% more than usual). Both are ~monthly figures, so it's a
        /// like-for-like comparison. Infinity when there's no baseline.
        var delta: Double {
            if average == 0 { return last30 > 0 ? .infinity : 0 }
            return ((last30 - average) / average).doubleValue
        }
    }

    /// Number of complete past months covered by the current range —
    /// every range ends at the last complete month.
    private var monthCount: Int {
        let cal = Calendar.current
        let thisMonth = Insights.monthStart(Date())
        switch range {
        case .month: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .year: return 12
        case .fiveYears: return 60
        case .ytd:
            // Complete months since 1 January; in January, fall back to last month.
            return max(cal.component(.month, from: thisMonth) - 1, 1)
        case .qtd:
            // Complete months in the current quarter; if the quarter just
            // started, show the previous (complete) quarter instead.
            let inQuarter = (cal.component(.month, from: thisMonth) - 1) % 3
            return inQuarter == 0 ? 3 : inQuarter
        case .all:
            guard let earliest = transactions.map(\.date).min() else { return 6 }
            let from = Insights.monthStart(earliest)
            let lastComplete = cal.date(byAdding: .month, value: -1, to: thisMonth)!
            let diff = cal.dateComponents([.month], from: from, to: lastComplete).month ?? 0
            return max(diff + 1, 1)
        case .custom, .payday:
            return 6   // Custom/Payday aren't offered here; safe fallback.
        }
    }

    private var rows: [Row] {
        // monthCount complete past months; drop the in-progress current month.
        let past = Insights.monthlySeries(count: monthCount + 1, in: aggregated).dropLast()

        var categories = Set<String>()
        for m in past { categories.formUnion(m.byCategory.map(\.category)) }

        let conv = Insights.converter(for: aggregated)

        // Current month-to-date spend per category (base currency).
        let monthStart = Insights.monthStart(Date())
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!
        var thisMonth: [String: Decimal] = [:]
        var thisMonthMixed = Set<String>()
        for t in aggregated where t.isExpense && t.date >= monthStart && t.date < nextMonth {
            let (v, converted) = conv.value(t)
            thisMonth[t.categoryLabel, default: 0] += v
            if converted { thisMonthMixed.insert(t.categoryLabel) }
            categories.insert(t.categoryLabel)   // include categories active only this month
        }

        // Rolling last-30-days spend per category (base currency). The upper
        // bound (≤ now) is essential under amortisation: a spreadN lump becomes
        // N forward-dated slivers, so without it every not-yet-reached sliver
        // (up to N-1 months ahead) would be counted, inflating the figure back
        // to the full lump instead of the ~one month actually in the window.
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        var last30: [String: Decimal] = [:]
        var last30Mixed = Set<String>()
        for t in aggregated where t.isExpense && t.date >= cutoff && t.date <= now {
            let (v, converted) = conv.value(t)
            last30[t.categoryLabel, default: 0] += v
            if converted { last30Mixed.insert(t.categoryLabel) }
            categories.insert(t.categoryLabel)
        }

        // Per-month value of a category across the averaged window.
        func monthValues(_ category: String) -> [Decimal] {
            past.map { $0.byCategory.first { $0.category == category }?.amount ?? 0 }
        }

        func row(category: String, label: String) -> Row {
            return Row(category: category, label: label,
                       average: Insights.average(monthValues(category)),
                       last30: last30[category] ?? 0,
                       thisMonth: thisMonth[category] ?? 0,
                       averageMixed: past.contains { $0.byCategoryMixed.contains(category) },
                       last30Mixed: last30Mixed.contains(category),
                       thisMonthMixed: thisMonthMixed.contains(category))
        }

        // Group full names under their main category.
        let byMain = Dictionary(grouping: categories) { Insights.splitCategory($0).main }
        return byMain.map { main, names in
            let memberRows = names.map { name in
                row(category: name, label: Insights.splitCategory(name).sub ?? name)
            }
            // Sum the members month-by-month so the parent average is exact.
            let summed = (0..<past.count).map { i in
                names.reduce(Decimal(0)) { $0 + monthValues($1)[i] }
            }
            // A main with a single bare entry (no subs) stays a leaf.
            let isLeaf = names.count == 1 && Insights.splitCategory(names[0]).sub == nil
            return Row(category: main, label: main,
                       average: Insights.average(summed),
                       last30: memberRows.reduce(Decimal(0)) { $0 + $1.last30 },
                       thisMonth: memberRows.reduce(Decimal(0)) { $0 + $1.thisMonth },
                       averageMixed: memberRows.contains(where: \.averageMixed),
                       last30Mixed: memberRows.contains(where: \.last30Mixed),
                       thisMonthMixed: memberRows.contains(where: \.thisMonthMixed),
                       children: isLeaf ? nil : memberRows.sorted(using: sortOrder))
        }
        .sorted(using: sortOrder)
    }

    /// The date window the averages cover: first averaged month → start of
    /// the current (excluded) month.
    private var window: (start: Date, end: Date) {
        let end = Insights.monthStart(Date())
        let start = Calendar.current.date(byAdding: .month, value: -monthCount, to: end)!
        return (start, end)
    }

    /// Expenses behind the selected row: the averaged window *plus* the current
    /// month (so this month's spend, which the "This month" column reflects, is
    /// listed too — newest first). Parent rows have no ":" in their id and match
    /// every "Main:Sub" under them; child ids are full category names and match
    /// exactly.
    private var selectedTransactions: [FFTransaction] {
        guard let sel = selection else { return [] }
        let start = window.start
        // Through the end of the current calendar month, unlike the averaging
        // window which stops at its start.
        let end = Calendar.current.date(byAdding: .month, value: 1, to: Insights.monthStart(Date()))!
        return transactions.filter { t in
            guard t.isExpense, t.date >= start, t.date < end else { return false }
            let name = t.categoryName ?? "Uncategorised"
            return sel.contains(":") ? name == sel : Insights.splitCategory(name).main == sel
        }
    }

    private var subtitle: String {
        let plural = monthCount == 1 ? "" : "s"
        switch range {
        case .all: return "All \(monthCount) complete months"
        case .ytd: return "Year to date — \(monthCount) complete month\(plural)"
        case .qtd: return "Quarter to date — \(monthCount) complete month\(plural)"
        default: return "Average over \(monthCount) complete month\(plural)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .readableWidth()
                .padding(.top, 16)
                .padding(.bottom, 12)
            GeometryReader { geo in
                // Default: tall enough to show every top-level category
                // (header ≈ 28pt + ~25pt per row), capped so the bottom keeps room.
                let fitContent = 28.0 + Double(rows.count) * 25 + 12
                let maxTop = max(geo.size.height - 150, 120)
                let topHeight = min(max(splitHeight > 0 ? splitHeight : fitContent, 120), maxTop)

                VStack(spacing: 0) {
                    averagesTable
                        .frame(height: topHeight)
                    PaneDivider(current: topHeight, range: 120...maxTop) { splitHeight = $0 }
                    transactionsPane
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Averages")
    }

    /// In-view range + amortise bar, matching the Dashboard and Categories headers.
    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(subtitle)
                .appFont(.title3, weight: .semibold)
            Spacer()
            Toggle(isOn: $amortizeView.animation(.snappy)) {
                Label("Amortise", systemImage: "calendar.badge.clock")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("Amortise: spread transactions tagged spreadN (e.g. an annual insurance tagged spread12) evenly across N months, instead of counting the whole lump in the month it was paid. Shared with the Dashboard.")
            Picker("Range", selection: $rangeRaw) {
                ForEach(FlowRange.allCases.filter { $0 != .custom && $0 != .payday }) { r in
                    Text(r.rawValue).tag(r.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 430)
            .help("Months included in the average")
        }
        .animation(.snappy, value: rangeRaw)
    }

    private var averagesTable: some View {
        Table(rows, children: \.children, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Category", value: \.category) { row in
                HStack(spacing: 8) {
                    CategoryBadge(category: row.category)
                    Text(row.label)
                }
            }
            .width(min: 160, ideal: 240, max: 380)
            TableColumn("Avg / month", value: \.average) { row in
                Text(row.average.currency(currency, approx: row.averageMixed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)
            TableColumn("Last 30 days", value: \.last30) { row in
                Text(row.last30.currency(currency, approx: row.last30Mixed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)
            TableColumn("vs avg", value: \.delta) { row in
                deltaCell(row)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)
            TableColumn("This month so far", value: \.thisMonth) { row in
                Text(row.thisMonth.currency(currency, approx: row.thisMonthMixed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(130)
        }
        // The amber app accent makes a selected row wash out red/green figures;
        // a blue selection keeps them legible.
        .tint(.blue)
        .readableWidth()
    }

    /// A single arrow + percentage: how the last 30 days compares with the
    /// category's monthly average. Red up = spending more than usual, green
    /// down = less.
    @ViewBuilder
    private func deltaCell(_ row: Row) -> some View {
        if row.average == 0 && row.last30 == 0 {
            Text("—").foregroundStyle(.secondary)
        } else if row.average == 0 {
            // No baseline in the averaged window, but money spent recently.
            Label("new", systemImage: "arrow.up")
                .labelStyle(.titleAndIcon)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.red)
        } else {
            let up = row.last30 > row.average
            let flat = row.last30 == row.average
            HStack(spacing: 3) {
                Image(systemName: flat ? "minus" : (up ? "arrow.up" : "arrow.down"))
                    .appFont(.caption, weight: .bold)
                Text("\(Int((abs(row.delta) * 100).rounded()))%").monospacedDigit()
            }
            .foregroundStyle(flat ? Color.secondary : (up ? Color.red : Color.green))
        }
    }

    @ViewBuilder
    private var transactionsPane: some View {
        if let selection {
            TransactionPane(title: selection,
                            transactions: selectedTransactions,
                            currency: currency)
        } else {
            ContentUnavailableView("Select a category",
                                   systemImage: "list.bullet.rectangle",
                                   description: Text("Click a row above to see its transactions over the selected period, including this month."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
