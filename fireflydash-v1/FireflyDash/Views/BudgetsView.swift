import SwiftUI
import SwiftData

/// "How much of this cycle's essential spending is used, and what's still
/// coming?" — driven entirely by `Insights.essentialProjection`: essential
/// categories are marked in Settings, recurring bills (rent, insurance,
/// subscriptions) are detected per biller from their own historical cadence,
/// and variable essential categories (groceries, fuel) fall back to a
/// historical monthly average. There is no manual target to set — the
/// "expected total" below is always computed from your own transaction
/// history.
struct BudgetsView: View {
    @Query private var allTransactions: [FFTransaction]
    @Query private var piggyBanks: [FFPiggyBank]
    /// Which pay period is shown; 0 = current (in-progress) one. Lets you page
    /// back to check whether past periods met expectations.
    @AppStorage("budgetPeriodTS") private var budgetPeriodTS = 0.0
    // Dataset-scoped, matching Settings/Dashboard/PiggyBanksView's own copies
    // of the same keys.
    @AppStorage("useSampleData") private var useSampleData = false
    @AppStorage("essentialPiggyGroups") private var essentialPiggyGroupsRealRaw = ""
    @AppStorage("sample.essentialPiggyGroups") private var essentialPiggyGroupsSampleRaw = ""
    @AppStorage("piggyPeriodSnapshot") private var piggySnapshotRealRaw = ""
    @AppStorage("sample.piggyPeriodSnapshot") private var piggySnapshotSampleRaw = ""
    private var essentialPiggyGroups: Set<String> {
        let raw = useSampleData ? essentialPiggyGroupsSampleRaw : essentialPiggyGroupsRealRaw
        return Set(raw.split(separator: "\n").map(String.init))
    }
    private var piggySnapshotRaw: String {
        get { useSampleData ? piggySnapshotSampleRaw : piggySnapshotRealRaw }
        nonmutating set { if useSampleData { piggySnapshotSampleRaw = newValue } else { piggySnapshotRealRaw = newValue } }
    }

    private var visible: [FFTransaction] { Insights.visible(allTransactions) }
    private var base: String { Insights.baseCurrency(visible) }

    /// Distinct paycheck dates (Settings → paycheck keyword), ascending.
    /// Essentials/bills are inherently a "since I got paid" concept, so pay
    /// periods — not calendar months — are what this view browses.
    private var paycheckDates: [Date] {
        let cal = Calendar.current
        let dates = Set(allTransactions.filter(Insights.isPaycheck).map { cal.startOfDay(for: $0.date) })
        return dates.sorted()
    }

    // MARK: Pay-period state
    //
    // Everything below (starts/current index/selected index/period/projection)
    // is a pure function of `allTransactions` + a couple of @AppStorage flags,
    // but each is a plain, uncached Swift computed property. On a small demo
    // dataset that's unnoticeable; on years of real transaction history it
    // becomes very expensive (a full-history scan + grouping + sorting per
    // call), and `body` used to reference this chain — directly or via
    // `spent`/`expectedRemaining`/`target`/`fraction`/`note` — around 15-20
    // times per render, each re-deriving from scratch. That multiplicative
    // cost is what pinned the CPU and kept the window from ever appearing.
    // `PeriodState` computes the whole chain exactly once per render; `body`
    // builds one and threads it through as plain data.
    private struct PeriodState {
        let starts: [Date]
        let currentIndex: Int
        let selectedIndex: Int
        let isCurrent: Bool
        let period: (start: Date, end: Date)
        let projection: Insights.EssentialProjection
        let spent: Decimal
        let expectedRemaining: Decimal
        let target: Decimal
        let fraction: Double
        let daysLeft: Int
        let periodLabel: String
        /// How far through the period "now" is (0–1) — a marker on the
        /// progress bar so the essential-spend fill can be read against where
        /// you actually are in the cycle, not just against the fill alone.
        let paceFraction: Double
        /// What should go into the Settings-selected "essential" piggy
        /// groups this period — nil when no groups are selected, or nothing
        /// is due. Uses the same frozen per-piggy tracking as the Dashboard
        /// (see `PiggyProgress`) so it agrees with it and actually reaches
        /// zero once paid, rather than a fresh recompute that wouldn't.
        let piggyCommitment: PiggyProgress.Commitment?
    }

    private func short(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

    private func makeState() -> PeriodState {
        let dates = paycheckDates
        let starts = dates.isEmpty ? [Insights.monthStart(Date())] : dates
        let currentIndex = starts.count - 1
        let selectedIndex: Int = {
            guard budgetPeriodTS != 0,
                  let idx = starts.firstIndex(where: { $0.timeIntervalSinceReferenceDate == budgetPeriodTS })
            else { return currentIndex }
            return idx
        }()
        let isCurrent = selectedIndex == currentIndex
        let start = starts[selectedIndex]
        let period: (start: Date, end: Date) = isCurrent
            ? (start, dates.isEmpty
                ? Calendar.current.date(byAdding: .month, value: 1, to: start)!
                : Insights.nextPaycheckEstimate(after: start, in: allTransactions))
            : (start, starts[selectedIndex + 1])

        let projection = Insights.essentialProjection(window: period, asOf: min(Date(), period.end),
                                                       in: allTransactions)
        let spent = projection.spentSoFar
        let expectedRemaining = projection.expectedRemaining
        let target = spent + expectedRemaining
        let fraction = target <= 0 ? 0 : (spent / target).doubleValue
        let daysLeft = max(Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: Date()), to: period.end).day ?? 0, 0)
        let periodLabel = isCurrent
            ? "Since \(short(period.start))"
            : "\(short(period.start)) – \(short(Calendar.current.date(byAdding: .day, value: -1, to: period.end)!))"
        let periodDays = max(Calendar.current.dateComponents(
            [.day], from: period.start, to: period.end).day ?? 1, 1)
        let elapsedDays = max(Calendar.current.dateComponents(
            [.day], from: period.start, to: min(Date(), period.end)).day ?? 0, 0)
        let paceFraction = min(max(Double(elapsedDays) / Double(periodDays), 0), 1)

        // Only meaningful for the in-progress period — PiggyProgress tracks
        // live progress against the CURRENT pay period's own anchor, so it
        // doesn't have anything sensible to say about a closed past one.
        let piggyCommitment: PiggyProgress.Commitment? = {
            guard isCurrent, !essentialPiggyGroups.isEmpty else { return nil }
            let scoped = piggyBanks.filter { essentialPiggyGroups.contains($0.objectGroup ?? "Ungrouped") }
            guard !scoped.isEmpty else { return nil }
            let conv = Insights.converter(for: visible)
            let result = PiggyProgress.commitment(piggyBanks: scoped, window: period,
                                                   rawSnapshot: piggySnapshotRaw, converter: conv)
            if result.rawSnapshot != piggySnapshotRaw { piggySnapshotRaw = result.rawSnapshot }
            return result.commitment
        }()

        return PeriodState(starts: starts, currentIndex: currentIndex, selectedIndex: selectedIndex,
                            isCurrent: isCurrent, period: period, projection: projection, spent: spent,
                            expectedRemaining: expectedRemaining, target: target, fraction: fraction,
                            daysLeft: daysLeft, periodLabel: periodLabel, paceFraction: paceFraction,
                            piggyCommitment: piggyCommitment)
    }

    /// Page between pay periods, never past the current (in-progress) one.
    /// Only runs on a button tap, so re-deriving `PeriodState` here (rather
    /// than threading it in) is fine — this isn't part of the render path.
    private func shiftPeriod(_ delta: Int) {
        let state = makeState()
        withAnimation(.snappy) {
            let target = max(0, min(state.selectedIndex + delta, state.currentIndex))
            budgetPeriodTS = target == state.currentIndex ? 0 : state.starts[target].timeIntervalSinceReferenceDate
        }
    }

    // MARK: Body

    var body: some View {
        let state = makeState()
        let base = base
        ScrollView {
            VStack(spacing: 20) {
                gaugeCard(state: state, base: base)
                if let piggyCommitment = state.piggyCommitment {
                    piggyCard(commitment: piggyCommitment, base: base)
                }
                if !state.projection.bills.isEmpty || !state.projection.variableCategories.isEmpty {
                    essentialsCard(projection: state.projection, base: base)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Budgets")
    }

    private func gaugeCard(state: PeriodState, base: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { shiftPeriod(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(state.selectedIndex == 0)
                Text(state.periodLabel)
                    .appFont(.title3, weight: .semibold)
                    .frame(minWidth: 220)
                Button { shiftPeriod(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(state.isCurrent)
                Button("Current period") {
                    withAnimation(.snappy) { budgetPeriodTS = 0 }
                }
                .disabled(state.isCurrent)
                Spacer()
            }
            .buttonStyle(.borderless)
            if state.isCurrent {
                HStack(alignment: .top, spacing: 24) {
                    kpi("Essential spend", state.spent.currency(base, approx: state.projection.mixed), .primary)
                    kpi("Discretionary spend", state.projection.discretionarySpentSoFar.currency(base, approx: state.projection.discretionaryMixed), .secondary)
                    kpi("Still to come", state.expectedRemaining.currency(base, approx: state.projection.mixed), .orange)
                    kpi("Expected total", state.target.currency(base, approx: state.projection.mixed), .secondary)
                }
                progressBar(height: 16, fraction: state.fraction, pace: state.paceFraction)
                Text(note(state: state, base: base))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text("Essential = tagged \"\(Insights.essentialTag())\" in Firefly. Discretionary = everything else. Only essential spend counts toward the gauge above; the vertical line on the bar marks how far through the period today is.")
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    kpi("Essential spend", state.spent.currency(base, approx: state.projection.mixed), .primary)
                    kpi("Discretionary spend", state.projection.discretionarySpentSoFar.currency(base, approx: state.projection.discretionaryMixed), .secondary)
                }
                Text("This pay period is closed — every essential bill has already posted.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// What should go into the Settings-selected "essential" piggy groups
    /// this period (Settings → Income & Savings → "Essential piggy groups")
    /// — for goals like an annual insurance premium that's saved toward
    /// gradually via a piggy bank rather than tracked as a Firefly bill.
    private func piggyCard(commitment: PiggyProgress.Commitment, base: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Piggy banks this period", systemImage: "banknote")
                    .appFont(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(commitment.amount.currency(base, approx: commitment.mixed))
                    .appFont(.headline).monospacedDigit().foregroundStyle(.orange)
            }
            ForEach(commitment.breakdown, id: \.key) { item in
                HStack {
                    Text(item.key)
                    Spacer()
                    Text(item.amount.currency(base, approx: item.mixed)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text("From your essential piggy groups (Settings → Income & Savings) — how much still needs to go in this period toward each goal's own deadline, tracked the same way the Dashboard tracks it (paying it in Firefly, or using \"Mark as paid this period\" in Piggy banks, brings this to zero).")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Every essential expected this period, bills AND variable categories
    /// together — replaces the old bills-only list, since a category like
    /// groceries (no single biller, historical-average projected) is just as
    /// much a real part of "Still to come" as rent or insurance is, and
    /// leaving it un-itemized was the #1 source of confusion in this view.
    private func essentialsCard(projection: Insights.EssentialProjection, base: String) -> some View {
        let billsPaid = projection.bills.filter(\.alreadyPaidThisPeriod).reduce(Decimal(0)) { $0 + $1.typicalAmount }
        let billsExpected = projection.bills.filter { !$0.alreadyPaidThisPeriod }.reduce(Decimal(0)) { $0 + $1.typicalAmount }
        let variableSpent = projection.variableCategories.reduce(Decimal(0)) { $0 + $1.spentSoFar }
        let variableExpected = projection.variableCategories.reduce(Decimal(0)) { $0 + $1.remaining }
        // Not every essential transaction lands in `bills`/`variableCategories`
        // — a biller with fewer than 3 historical occurrences (a brand-new
        // essential expense, say) falls through both detection paths and is
        // never itemized, but it's still real essential spend counted in the
        // gauge's "Essential spend" above. Rather than let "Paid" here quietly
        // undercount that, the gap is surfaced as its own line so the two
        // totals are provably the same figure, just sliced differently.
        let otherPaid = max(0, projection.spentSoFar - billsPaid - variableSpent)
        let paidTotal = billsPaid + variableSpent + otherPaid
        let expectedTotal = billsExpected + variableExpected
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Essentials this period", systemImage: "repeat.circle")
                    .appFont(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Paid \(paidTotal.currency(base))").appFont(.caption).foregroundStyle(.green)
                Text("· Still expected \(expectedTotal.currency(base))").appFont(.caption).foregroundStyle(.orange)
            }
            ForEach(projection.bills) { bill in
                HStack(spacing: 10) {
                    CategoryBadge(category: bill.category, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bill.biller ?? bill.category)
                        Text(bill.category)
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(bill.typicalAmount.currency(base)).monospacedDigit()
                        Text(bill.alreadyPaidThisPeriod
                             ? "Paid \(bill.lastPaidDate.formatted(.dateTime.month(.abbreviated).day()))"
                             : "Expected \(bill.expectedDate.formatted(.dateTime.month(.abbreviated).day()))")
                            .appFont(.caption2)
                            .foregroundStyle(bill.alreadyPaidThisPeriod ? .green : .orange)
                    }
                }
            }
            ForEach(projection.variableCategories) { v in
                HStack(spacing: 10) {
                    CategoryBadge(category: v.category, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.category)
                        Text("Variable — historical average")
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(v.expectedTotal.currency(base)).monospacedDigit()
                        Text(v.remaining <= 0
                             ? "Spent \(v.spentSoFar.currency(base)) — done"
                             : "Spent \(v.spentSoFar.currency(base)) of ~\(v.expectedTotal.currency(base))")
                            .appFont(.caption2)
                            .foregroundStyle(v.remaining <= 0 ? .green : .orange)
                    }
                }
            }
            if otherPaid > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Other essential spend")
                        Text("Not enough history to itemize yet")
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(otherPaid.currency(base)).monospacedDigit()
                }
            }
            Text("Everything counted in the gauge above, itemized: recurring bills (rent, insurance, subscriptions — detected per biller from their own cadence) whether already paid or still expected, plus variable essential categories with many small transactions instead (groceries, fuel) — those are estimated from your historical monthly average rather than a fixed date. \"Other essential spend\" covers anything essential-tagged that's too new or sparse to detect a pattern from (fewer than 3 past occurrences) — it's real spend already counted in \"Paid\" above, just not yet predictable enough to show a typical amount or cadence for.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Pieces

    private func kpi(_ title: String, _ value: String, _ color: Color, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            Text(value).appFont(.title2, weight: .semibold).monospacedDigit().foregroundStyle(color)
            if let sub { Text(sub).appFont(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spent-vs-expected-total fill. Essential spend is naturally front-loaded
    /// (rent/subscriptions land early in the cycle), so unlike a flat manual
    /// cap this isn't a pace warning — just how much of the expected total has
    /// already gone out. `pace` (0–1, optional) marks how far through the
    /// period today is, so the fill can be read against actual elapsed time.
    private func progressBar(height: CGFloat, fraction: Double, pace: Double? = nil) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color.accentColor)
                    .frame(width: min(max(fraction, 0), 1) * w)
                if let pace {
                    Rectangle()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: 2, height: height)
                        .offset(x: min(max(pace, 0), 1) * w - 1)
                }
            }
        }
        .frame(height: height)
    }

    private func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    private func note(state: PeriodState, base: String) -> String {
        let spentStr = state.spent.currency(base, approx: state.projection.mixed)
        let targetStr = state.target.currency(base, approx: state.projection.mixed)
        if state.expectedRemaining <= 0 {
            return "No more essential bills detected before payday — \(spentStr) spent so far (\(percent(state.fraction)) of the expected total)."
        }
        return "\(state.expectedRemaining.currency(base, approx: state.projection.mixed)) of essentials still expected before payday (of a \(targetStr) expected total), with \(state.daysLeft) day\(state.daysLeft == 1 ? "" : "s") left this period."
    }
}
