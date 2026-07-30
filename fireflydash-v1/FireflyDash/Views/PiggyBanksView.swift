import SwiftUI
import SwiftData

/// Savings goals (Firefly "piggy banks"), grouped like Firefly's own page:
/// an overall KPI summary, then each object group with per-goal progress,
/// amounts, "left to save" and Firefly's suggested monthly contribution.
struct PiggyBanksView: View {
    @Query private var piggies: [FFPiggyBank]
    @Query private var allTransactions: [FFTransaction]
    @Query private var accounts: [FFAccount]

    /// User's custom group order (unit-separator–joined titles). When empty,
    /// Firefly's own ordering is used. Groups dragged in the UI are persisted here.
    @AppStorage("piggyGroupOrder") private var groupOrderRaw = ""
    /// Group title currently hovered as a drop target, for a highlight.
    @State private var dropTarget: String?

    // Piggies excluded from the Dashboard's monthly savings plan are dataset-scoped,
    // same as every other content-referencing setting (piggy IDs only exist per dataset).
    @AppStorage("useSampleData") private var useSampleData = false
    @AppStorage("piggyPlanExcluded") private var planExcludedRealRaw = ""
    @AppStorage("sample.piggyPlanExcluded") private var planExcludedSampleRaw = ""
    private var planExcludedRaw: String {
        get { useSampleData ? planExcludedSampleRaw : planExcludedRealRaw }
        nonmutating set { if useSampleData { planExcludedSampleRaw = newValue } else { planExcludedRealRaw = newValue } }
    }
    private var planExcluded: Set<String> {
        Set(planExcludedRaw.split(separator: "\n").map(String.init))
    }
    private func togglePlanExcluded(_ piggyID: String) {
        var set = planExcluded
        if set.contains(piggyID) { set.remove(piggyID) } else { set.insert(piggyID) }
        planExcludedRaw = set.sorted().joined(separator: "\n")
    }

    // Piggy-period progress (see PiggyProgress.swift) is dataset-scoped like
    // everything else here.
    @AppStorage("piggyPeriodSnapshot") private var piggySnapshotRealRaw = ""
    @AppStorage("sample.piggyPeriodSnapshot") private var piggySnapshotSampleRaw = ""
    private var piggySnapshotRaw: String {
        get { useSampleData ? piggySnapshotSampleRaw : piggySnapshotRealRaw }
        nonmutating set { if useSampleData { piggySnapshotSampleRaw = newValue } else { piggySnapshotRealRaw = newValue } }
    }

    /// Records that this piggy's due share has already been paid this pay
    /// period, so the Dashboard's "still needed" total reflects it right
    /// away instead of a fresh recompute that — for a long-horizon goal —
    /// wouldn't actually reach zero from a single installment.
    private func markPaidThisPeriod(_ p: FFPiggyBank) {
        guard let anchor = PiggyProgress.periodAnchor(in: allTransactions) else { return }
        let baseline = converter.convert(p.leftToSave, from: p.currencyCode).amount
        piggySnapshotRaw = PiggyProgress.markSettled(rawSnapshot: piggySnapshotRaw, piggyID: p.piggyID,
                                                      currentLeftToSave: baseline, anchor: anchor)
    }

    /// Whether this piggy currently carries a manual "mark as paid" for the
    /// pay period in progress (a leftover mark from an earlier period doesn't
    /// count — a fresh period always starts unmarked).
    private func isMarkedPaid(_ p: FFPiggyBank) -> Bool {
        guard let anchor = PiggyProgress.periodAnchor(in: allTransactions) else { return false }
        return PiggyProgress.isMarkedSettled(rawSnapshot: piggySnapshotRaw, piggyID: p.piggyID, anchor: anchor)
    }

    /// Undoes a manual "mark as paid" — the piggy's frozen target/baseline
    /// for this period are dropped, so the Dashboard re-freezes it fresh
    /// from current numbers, same as any newly-tracked goal.
    private func unmarkPaid(_ p: FFPiggyBank) {
        guard let anchor = PiggyProgress.periodAnchor(in: allTransactions) else { return }
        piggySnapshotRaw = PiggyProgress.clearOverride(rawSnapshot: piggySnapshotRaw, piggyID: p.piggyID, anchor: anchor)
    }

    private var base: String { Insights.baseCurrency(allTransactions) }
    private var converter: CurrencyConverter { Insights.converter(for: allTransactions) }

    /// Two-column matrix kicks in once the window is wide enough to hold it.
    private let twoColumnThreshold: CGFloat = 980

    /// Piggies grouped by object group. Firefly's own ordering (ungrouped first,
    /// then by group order) is the default; any saved custom order takes priority.
    private var groups: [(title: String, items: [FFPiggyBank])] {
        let sorted = piggies.sorted {
            ($0.groupOrder, $0.order, $0.name) < ($1.groupOrder, $1.order, $1.name)
        }
        var fireflyOrder: [String] = []
        var map: [String: [FFPiggyBank]] = [:]
        for p in sorted {
            let key = p.objectGroup ?? "Ungrouped"
            if map[key] == nil { fireflyOrder.append(key) }
            map[key, default: []].append(p)
        }
        // Saved order first (skipping titles that no longer exist), then any new
        // groups appended in Firefly's order.
        let saved = groupOrderRaw.split(separator: "\u{1F}").map(String.init)
        var ordered = saved.filter { map[$0] != nil }
        for title in fireflyOrder where !ordered.contains(title) { ordered.append(title) }
        return ordered.map { (title: $0, items: map[$0]!) }
    }

    /// Persist a reordered list of group titles.
    private func saveOrder(_ titles: [String]) {
        groupOrderRaw = titles.joined(separator: "\u{1F}")
    }

    /// Move the dragged group so it lands in `target`'s position.
    private func moveGroup(_ dragged: String, onto target: String) {
        guard dragged != target else { return }
        var titles = groups.map(\.title)
        guard let from = titles.firstIndex(of: dragged) else { return }
        titles.remove(at: from)
        guard let to = titles.firstIndex(of: target) else { return }
        titles.insert(dragged, at: to)
        saveOrder(titles)
    }

    /// Saved / target across all goals, in base currency.
    private var totals: (saved: Decimal, target: Decimal, mixed: Bool) {
        sumInBase(piggies)
    }

    private var fundedCount: Int { piggies.filter { $0.targetAmount > 0 && $0.fraction >= 1 }.count }
    private var goalCount: Int { piggies.filter { $0.targetAmount > 0 }.count }

    private func sumInBase(_ items: [FFPiggyBank]) -> (saved: Decimal, target: Decimal, mixed: Bool) {
        var saved: Decimal = 0, target: Decimal = 0, mixed = false
        for p in items {
            let (s, sc) = converter.convert(p.currentAmount, from: p.currencyCode)
            let (t, tc) = converter.convert(p.targetAmount, from: p.currencyCode)
            saved += s; target += t
            if sc || tc { mixed = true }
        }
        return (saved, target, mixed)
    }

    /// A group's subtotal in its own currency when uniform, else base (≈).
    private func groupTotals(_ items: [FFPiggyBank]) -> (saved: Decimal, target: Decimal, currency: String, mixed: Bool) {
        let currencies = Set(items.map(\.currencyCode))
        if currencies.count == 1, let cc = currencies.first {
            return (items.reduce(0) { $0 + $1.currentAmount },
                    items.reduce(0) { $0 + $1.targetAmount }, cc, false)
        }
        let t = sumInBase(items)
        return (t.saved, t.target, base, true)
    }

    /// How much a group's active goals need over a rolling one-month window
    /// from today — `Insights.piggyNeed` per piggy (same window-share logic as
    /// the Dashboard's "this period" figure, just spanning a full month here),
    /// summed in base currency. Unlike the Dashboard's commitment total this
    /// ignores the plan-exclusion toggle: it's a general "what does this group
    /// need per month" summary, not the forced monthly-savings-plan figure.
    private func groupMonthlyNeed(_ items: [FFPiggyBank], asOf: Date = Date()) -> (amount: Decimal, mixed: Bool) {
        let end = Calendar.current.date(byAdding: .month, value: 1, to: asOf)!
        var total: Decimal = 0
        var mixed = false
        for p in items {
            let need = Insights.piggyNeed(p, window: (asOf, end), asOf: asOf)
            guard need > 0 else { continue }
            let (v, converted) = converter.convert(need, from: p.currencyCode)
            total += v
            if converted { mixed = true }
        }
        return (total, mixed)
    }

    var body: some View {
        GeometryReader { geo in
            let twoColumn = geo.size.width >= twoColumnThreshold
            ScrollView {
                if piggies.isEmpty {
                    ContentUnavailableView("No piggy banks",
                        systemImage: "banknote",
                        description: Text("Create savings goals in Firefly, then refresh to track them here."))
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 20) {
                        summaryCard
                        groupGrid(twoColumn: twoColumn)
                        accountStatusCard
                    }
                    .padding(24)
                    .frame(maxWidth: twoColumn ? 1480 : 880)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Piggy banks")
    }

    /// The group cards, laid out as a single column or a two-column matrix.
    @ViewBuilder
    private func groupGrid(twoColumn: Bool) -> some View {
        let columns = twoColumn
            ? [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
            : [GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(groups, id: \.title) { group in
                groupCard(group.title, group.items)
                    .overlay {
                        if dropTarget == group.title {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .draggable(group.title) {
                        // Lightweight drag preview.
                        Label(group.title, systemImage: "line.3.horizontal")
                            .padding(8)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .dropDestination(for: String.self) { items, _ in
                        dropTarget = nil
                        guard let dragged = items.first else { return false }
                        moveGroup(dragged, onto: group.title)
                        return true
                    } isTargeted: { over in
                        dropTarget = over ? group.title : (dropTarget == group.title ? nil : dropTarget)
                    }
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let t = totals
        let frac = t.target > 0 ? (t.saved / t.target).doubleValue : 0
        return HStack(alignment: .center, spacing: 24) {
            ProgressRing(fraction: frac, tint: .green,
                         label: "\(Int((frac * 100).rounded()))%")
                .scaledFrame(104)
            VStack(alignment: .leading, spacing: 12) {
                Text("Savings goals").appFont(.headline).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 28) {
                    kpi("Saved so far", t.saved.currency(base, approx: t.mixed), .green)
                    kpi("Of target", t.target.currency(base, approx: t.mixed), .secondary)
                    kpi("Left to save", max(t.target - t.saved, 0).currency(base, approx: t.mixed), .primary)
                }
                if goalCount > 0 {
                    Text("\(fundedCount) of \(goalCount) goals fully funded")
                        .appFont(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Group card

    private func groupCard(_ title: String, _ items: [FFPiggyBank]) -> some View {
        let g = groupTotals(items)
        let frac = g.target > 0 ? (g.saved / g.target).doubleValue : 0
        let monthly = groupMonthlyNeed(items)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .appFont(.caption)
                            .foregroundStyle(.tertiary)
                            .help("Drag to reorder groups")
                        Text(title).appFont(.headline)
                    }
                    Text("\(g.saved.currency(g.currency, approx: g.mixed)) / \(g.target.currency(g.currency, approx: g.mixed))")
                        .appFont(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    if monthly.amount > 0 {
                        Label("\(monthly.amount.currency(base, approx: monthly.mixed))/mo needed",
                              systemImage: "calendar")
                            .appFont(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .help("This group's active goals' combined need over a rolling one-month window, in \(base).")
                    }
                }
                Spacer(minLength: 8)
                if g.target > 0 {
                    ProgressRing(fraction: frac, tint: .green, lineWidth: 7,
                                 label: "\(Int((frac * 100).rounded()))%",
                                 labelStyle: .subheadline, labelWeight: .bold)
                        .scaledFrame(56)
                }
            }
            Divider()
            VStack(spacing: 14) {
                ForEach(items) { piggyRow($0) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func piggyRow(_ p: FFPiggyBank) -> some View {
        let hasTarget = p.targetAmount > 0
        let funded = hasTarget && p.fraction >= 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if funded {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Text(p.name).fontWeight(.medium)
                Spacer()
                if hasTarget {
                    Text("\(p.currentAmount.currency(p.currencyCode)) / \(p.targetAmount.currency(p.currencyCode))")
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(p.currentAmount.currency(p.currencyCode))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if hasTarget {
                progressBar(p.fraction)
                HStack(spacing: 6) {
                    Text("\(Int((p.fraction * 100).rounded()))% saved")
                    if p.leftToSave > 0 {
                        Text("· \(p.leftToSave.currency(p.currencyCode)) to go")
                    }
                    Spacer()
                    if p.savePerMonth > 0 {
                        Label("\(p.savePerMonth.currency(p.currencyCode))/mo", systemImage: "calendar")
                    }
                    if let date = p.targetDate {
                        Text("by \(date.formatted(.dateTime.month(.abbreviated).year()))")
                    }
                }
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                if Insights.piggyIsActive(p) {
                    HStack(spacing: 12) {
                        Toggle("Count in monthly plan", isOn: Binding(
                            get: { !planExcluded.contains(p.piggyID) },
                            set: { _ in togglePlanExcluded(p.piggyID) }))
                            .toggleStyle(.checkbox)
                            .help("Included in the Dashboard's \"still to come\" savings estimate. Untick if this goal shouldn't be forced every pay period.")
                        if isMarkedPaid(p) {
                            Label("Paid this period", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .help("This goal is marked settled for the current pay period, so the Dashboard shows €0 still due for it.")
                            Button("Undo", role: .destructive) { unmarkPaid(p) }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .help("Remove the \"paid\" mark — the Dashboard will go back to computing this goal's due share fresh from its current balance.")
                        } else {
                            Button { markPaidThisPeriod(p) } label: {
                                Label("Mark as paid this period", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .help("Record that you've already contributed this goal's due share this pay period, so the Dashboard's \"still needed\" total drops right away instead of waiting on a recompute that a long-horizon goal wouldn't otherwise satisfy from a single payment.")
                        }
                    }
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No target set")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Account status

    private struct AccountStatusRow: Identifiable {
        let id: String
        let name: String
        let balance: Decimal
        let allocated: Decimal
        let approx: Bool
        var free: Decimal { balance - allocated }
        var fraction: Double { balance > 0 ? min(max((allocated / balance).doubleValue, 0), 1) : 0 }
    }

    /// One row per asset account that has piggies attached: its balance, how much
    /// is committed to piggies, and what's free — all in base currency.
    private var accountStatus: [AccountStatusRow] {
        let withAccount = piggies.compactMap { p -> (String, FFPiggyBank)? in
            guard let id = p.accountID else { return nil }
            return (id, p)
        }
        guard !withAccount.isEmpty else { return [] }
        let byAccount = Dictionary(grouping: withAccount, by: \.0)
            .mapValues { $0.map(\.1) }
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.accountID, $0) })
        var rows: [AccountStatusRow] = []
        for (accID, items) in byAccount {
            let acct = accountByID[accID]
            let name = acct?.name ?? items.first?.accountName ?? "Account \(accID)"
            var approx = false
            let balance: Decimal
            if let acct {
                let (b, c) = converter.convert(acct.currentBalance, from: acct.currencyCode)
                balance = b; approx = approx || c
            } else {
                balance = 0
            }
            var allocated: Decimal = 0
            for p in items {
                let (a, c) = converter.convert(p.currentAmount, from: p.currencyCode)
                allocated += a; approx = approx || c
            }
            rows.append(AccountStatusRow(id: accID, name: name, balance: balance,
                                         allocated: allocated, approx: approx))
        }
        return rows.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var accountStatusCard: some View {
        let rows = accountStatus
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Account status").appFont(.headline)
                Text("How much of each account's balance is committed to piggy banks.")
                    .appFont(.caption).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow {
                        Text("Account")
                        Text("Balance").gridColumnAlignment(.trailing)
                        Text("In piggies").gridColumnAlignment(.trailing)
                        Text("Free").gridColumnAlignment(.trailing)
                    }
                    .appFont(.caption).foregroundStyle(.secondary)
                    ForEach(rows) { row in
                        GridRow {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.name).fontWeight(.medium)
                                progressBar(row.fraction, height: 5).frame(width: 180)
                            }
                            Text(row.balance.currency(base, approx: row.approx))
                                .monospacedDigit()
                            Text(row.allocated.currency(base, approx: row.approx))
                                .monospacedDigit().foregroundStyle(.green)
                            Text(row.free.currency(base, approx: row.approx))
                                .monospacedDigit()
                                .foregroundStyle(row.free < 0 ? .red : .secondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Pieces

    private func kpi(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            Text(value).appFont(.title3, weight: .semibold).monospacedDigit().foregroundStyle(color)
        }
    }

    private func progressBar(_ fraction: Double, height: CGFloat = 8) -> some View {
        GeometryReader { geo in
            Capsule().fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule().fill(.green)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: height)
    }
}

/// A circular progress gauge for KPI headers.
struct ProgressRing: View {
    let fraction: Double
    var tint: Color = .green
    var lineWidth: CGFloat = 11
    var label: String?
    var labelStyle: Font.TextStyle = .title3
    var labelWeight: Font.Weight = .bold

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label).appFont(labelStyle, weight: labelWeight).monospacedDigit()
            }
        }
    }
}
