import SwiftUI
import SwiftData
import Charts

/// Categories as a tree (Main → Main:Sub), opening on an all-time pie of main
/// categories. Selection is a plain String: "" = overview, "Main" = whole main
/// category (subs rolled up), "Main:Sub" = one subcategory.
struct CategoriesView: View {
    @Query private var allTransactions: [FFTransaction]
    @State private var selected: String = ""
    /// Month clicked in the drill-down column chart; nil = no month selected.
    @State private var selectedMonth: Date?
    @AppStorage("categoriesRange") private var rangeRaw = FlowRange.all.rawValue
    /// Height of the chart pane in the drill-down split; 0 = default.
    @AppStorage("categoriesSplitHeight") private var splitHeight = 0.0
    /// Single month to focus the overview on (set by the Dashboard trend
    /// chart); 0 = follow the range picker instead.
    @AppStorage("categoriesMonth") private var monthOverrideTS = 0.0
    @AppStorage("subThresholdPercent") private var subThresholdPercent = 2.0

    private var range: FlowRange { FlowRange(rawValue: rangeRaw) ?? .all }

    private var monthOverride: Date? {
        monthOverrideTS == 0 ? nil : Date(timeIntervalSinceReferenceDate: monthOverrideTS)
    }

    private var transactions: [FFTransaction] { Insights.visible(allTransactions) }
    private var currency: String { Insights.baseCurrency(transactions) }

    struct TreeNode: Identifiable {
        var id: String { main }
        let main: String
        let total: Decimal
        /// (full category name, subcategory label, amount)
        let subs: [(full: String, label: String, amount: Decimal)]
    }

    /// All-time expense totals grouped by full category name.
    private var fullTotals: [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for t in transactions.filter(\.isExpense) {
            totals[t.categoryName ?? "Uncategorised", default: 0] += t.amount
        }
        return totals
    }

    /// Alphabetical tree of main categories with their subcategories.
    private var tree: [TreeNode] {
        var mains: [String: [(full: String, label: String, amount: Decimal)]] = [:]
        for (full, amount) in fullTotals {
            let (main, sub) = Insights.splitCategory(full)
            mains[main, default: []].append((full: full, label: sub ?? "", amount: amount))
        }
        return mains.map { main, entries in
            let subs = entries
                .filter { !$0.label.isEmpty }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            return TreeNode(main: main,
                            total: entries.reduce(Decimal(0)) { $0 + $1.amount },
                            subs: subs)
        }
        .sorted { $0.main.localizedCaseInsensitiveCompare($1.main) == .orderedAscending }
    }

    /// Does a transaction's category match the current selection?
    private func matches(_ categoryName: String?, selection: String) -> Bool {
        let name = categoryName ?? "Uncategorised"
        if selection.contains(":") { return name == selection }
        return Insights.splitCategory(name).main == selection
    }

    private var monthlyForSelected: [(month: Date, amount: Decimal)] {
        guard !selected.isEmpty else { return [] }
        let cal = Calendar.current
        let thisMonth = Insights.monthStart(Date())
        let conv = Insights.converter(for: transactions)
        let matching = transactions.filter { $0.isExpense && matches($0.categoryName, selection: selected) }
        return (0..<12).reversed().map { offset in
            let start = cal.date(byAdding: .month, value: -offset, to: thisMonth)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            let amount = matching.filter { $0.date >= start && $0.date < end }
                .reduce(Decimal(0)) { $0 + conv.value($1).amount }
            return (month: start, amount: amount)
        }
    }

    private var categoryList: some View {
        List(selection: $selected) {
            Label("All time overview", systemImage: "chart.pie")
                .tag("")
            ForEach(tree) { node in
                if node.subs.isEmpty {
                    categoryRow(node.main, full: node.main).tag(node.main)
                } else {
                    DisclosureGroup {
                        ForEach(node.subs, id: \.full) { sub in
                            categoryRow(sub.label, full: sub.full).tag(sub.full)
                        }
                    } label: {
                        categoryRow(node.main, full: node.main).tag(node.main)
                    }
                }
            }
        }
        .tint(.blue)
        .frame(minWidth: 220, maxWidth: 300)
    }

    private func categoryRow(_ label: String, full: String) -> some View {
        HStack(spacing: 8) {
            CategoryBadge(category: full, size: 18)
            Text(label)
        }
    }

    private var detailPane: some View {
        Group {
            if selected.isEmpty {
                allTimePie
            } else {
                categoryDetail(selected)
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity)
    }

    var body: some View {
        HSplitView {
            categoryList
            detailPane
        }
        .onChange(of: selected) { selectedMonth = nil }
        // A fresh month focus from the Dashboard always lands on the overview.
        .onChange(of: monthOverrideTS) { if monthOverrideTS != 0 { selected = "" } }
        .onAppear { if monthOverrideTS != 0 { selected = "" } }
        .navigationTitle("Categories")
    }

    // MARK: Overview pie (landing view) — main categories, subs rolled up

    /// Main-category expense totals within the selected range (base currency),
    /// with the per-subcategory breakdown for hover details.
    private var mainTotals: [Insights.MainEntry] {
        let (start, end): (Date, Date)
        if let m = monthOverride {
            start = m; end = Calendar.current.date(byAdding: .month, value: 1, to: m)!
        } else {
            (start, end) = range.window
        }
        let f = Insights.range(start: start, end: end, in: transactions)
        return Insights.collapseSmall(
            Insights.mainBreakdown(f.byCategory, mixedCategories: f.byCategoryMixed),
            thresholdPercent: subThresholdPercent)
    }

    private var pieTitle: String {
        if let m = monthOverride {
            return "\(m.formatted(.dateTime.month(.wide).year())) — where the money went"
        }
        switch range {
        case .month: return "This month — where the money went"
        case .threeMonths: return "Last 3 months — where the money went"
        case .sixMonths: return "Last 6 months — where the money went"
        case .ytd: return "Year to date — where the money went"
        case .qtd: return "Quarter to date — where the money went"
        case .year: return "Last 12 months — where the money went"
        case .fiveYears: return "Last 5 years — where the money went"
        case .all, .custom, .payday: return "All time — where the money went"
        }
    }

    private var allTimePie: some View {
        let mains = mainTotals
        let total = mains.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(pieTitle)
                    .appFont(.largeTitle, weight: .bold)
                Spacer()
                if monthOverride != nil {
                    Button {
                        monthOverrideTS = 0
                    } label: {
                        Label("Back to range", systemImage: "xmark.circle.fill")
                    }
                } else {
                    Picker("", selection: $rangeRaw) {
                        ForEach(FlowRange.allCases.filter { $0 != .custom && $0 != .payday }) { r in
                            Text(r.rawValue).tag(r.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 430)
                }
            }
            Text("Click a slice or pick a category on the left to drill in.")
                .foregroundStyle(.secondary)

            if mains.isEmpty {
                Text("No spending in this period.").foregroundStyle(.secondary)
                Spacer()
            } else {
                DonutListChart(
                    slices: mains.map { m in
                        .init(label: m.main, amount: m.amount,
                              color: CategoryStyle.color(m.main),
                              mixed: m.mixed,
                              detail: DonutListChart.subDetail(m.subs, currency: currency))
                    },
                    currency: currency,
                    centerTitle: "Total",
                    centerAmount: total,
                    // "Other" is a roll-up, not a real category — don't drill into it.
                    onSelect: { if $0 != "Other" { selected = $0 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.snappy, value: rangeRaw)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Category drill-down

    private func categoryDetail(_ cat: String) -> some View {
        GeometryReader { geo in
            let maxTop = max(geo.size.height - 150, 240)
            let topHeight = min(max(splitHeight > 0 ? splitHeight : 480, 240), maxTop)

            VStack(spacing: 0) {
                chartSection(cat)
                    .frame(height: topHeight)
                PaneDivider(current: topHeight, range: 240...maxTop) { splitHeight = $0 }
                monthPane(cat)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func chartSection(_ cat: String) -> some View {
        let data = monthlyForSelected
        let avg = Insights.average(data.map(\.amount)).doubleValue
        let (main, sub) = Insights.splitCategory(cat)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(main).appFont(.largeTitle, weight: .bold)
                if let sub {
                    Text("›").appFont(.title2).foregroundStyle(.secondary)
                    Text(sub).appFont(.title, weight: .semibold).foregroundStyle(.secondary)
                }
            }
            Text("Average \(Decimal(avg).currency(currency)) / month over the last year — click a column for its transactions")
                .foregroundStyle(.secondary)

            Chart {
                ForEach(data, id: \.month) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Spent", point.amount.doubleValue))
                        .foregroundStyle(point.month == selectedMonth
                                         ? Color.orange.gradient : CategoryStyle.color(main).gradient)
                        .cornerRadius(4)
                        .annotation(position: .top, overflowResolution:
                                        .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if point.amount > 0 {
                                Text(point.amount.currency(currency))
                                    .appFont(.caption2).foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                }
                RuleMark(y: .value("Average", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing, overflowResolution:
                                    .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text("avg \(Decimal(avg).currency(currency))")
                            .appFont(.caption, weight: .semibold)
                            .fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.background.secondary, in: Capsule())
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            let month = Insights.monthStart(date)
                            selectedMonth = selectedMonth == month ? nil : month
                        }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Bottom pane: the transactions behind the clicked column.
    @ViewBuilder
    private func monthPane(_ cat: String) -> some View {
        if let month = selectedMonth {
            let end = Calendar.current.date(byAdding: .month, value: 1, to: month)!
            let txs = transactions.filter {
                $0.isExpense && matches($0.categoryName, selection: cat)
                    && $0.date >= month && $0.date < end
            }
            TransactionPane(
                title: "\(cat) — \(month.formatted(.dateTime.month(.wide).year()))",
                transactions: txs,
                currency: currency)
        } else {
            ContentUnavailableView("Select a month",
                                   systemImage: "list.bullet.rectangle",
                                   description: Text("Click a column above to see its transactions."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AccountsView: View {
    @Query(sort: \FFAccount.name) private var accounts: [FFAccount]
    @Query private var allTransactions: [FFTransaction]
    @AppStorage("accountsSort") private var sortRaw = AccountSort.balance.rawValue

    enum AccountSort: String, CaseIterable, Identifiable {
        case name = "Name", balance = "Balance"
        var id: String { rawValue }
    }
    private var sort: AccountSort { AccountSort(rawValue: sortRaw) ?? .balance }

    private var assetAccounts: [FFAccount] {
        accounts.filter { $0.type == "asset" }
    }

    private var baseCurrency: String { Insights.baseCurrency(allTransactions) }

    /// Net worth in the base currency; flagged when it combines currencies.
    private var netWorth: (amount: Decimal, mixed: Bool) {
        let conv = Insights.converter(for: allTransactions)
        var total: Decimal = 0
        var mixed = false
        for account in assetAccounts {
            let (v, converted) = conv.convert(account.currentBalance, from: account.currencyCode)
            total += v
            if converted { mixed = true }
        }
        return (total, mixed)
    }

    /// Asset accounts grouped by their (single) currency — base currency
    /// first, then the rest alphabetically. Each group is ordered by the
    /// chosen sort.
    private var groups: [(currency: String, total: Decimal, accounts: [FFAccount])] {
        let byCurrency = Dictionary(grouping: assetAccounts, by: \.currencyCode)
        func ordered(_ list: [FFAccount]) -> [FFAccount] {
            switch sort {
            case .name: list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .balance: list.sorted { $0.currentBalance > $1.currentBalance }
            }
        }
        return byCurrency.map { code, list in
            (currency: code, total: list.reduce(Decimal(0)) { $0 + $1.currentBalance }, accounts: ordered(list))
        }
        .sorted { a, b in
            if a.currency == baseCurrency { return true }
            if b.currency == baseCurrency { return false }
            return a.currency < b.currency
        }
    }

    var body: some View {
        List {
            SwiftUI.Section {
                HStack {
                    Text("Net worth").appFont(.title2, weight: .semibold)
                    Spacer()
                    Text(netWorth.amount.currency(baseCurrency, approx: netWorth.mixed))
                        .appFont(.title2, weight: .bold)
                        .monospacedDigit()
                }
                .padding(.vertical, 8)
                .readableWidth()
            }
            ForEach(groups, id: \.currency) { group in
                SwiftUI.Section {
                    ForEach(group.accounts) { account in
                        HStack {
                            Label(account.name, systemImage: "building.columns")
                            Spacer()
                            Text(account.currentBalance.currency(account.currencyCode))
                                .monospacedDigit()
                                .foregroundStyle(account.currentBalance < 0 ? .red : .primary)
                        }
                        .readableWidth()
                    }
                } header: {
                    HStack {
                        Text(group.currency == baseCurrency
                             ? "\(group.currency) (base)" : group.currency)
                        Spacer()
                        Text(group.total.currency(group.currency))
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(AccountSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .help("Order accounts within each currency")
            }
        }
    }
}
