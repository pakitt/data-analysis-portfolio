import SwiftUI
import SwiftData
import Charts

/// Wide, distinct palette shared by the donut and Sankey so colours don't blur together.
enum Palette {
    static let colors: [Color] = [
        .blue, .orange, .green, .pink, .purple, .teal, .red, .yellow,
        .indigo, .mint, .brown, .cyan,
        Color(red: 0.6, green: 0.3, blue: 0.0),   // ochre
        Color(red: 0.0, green: 0.35, blue: 0.6),  // steel blue
        Color(red: 0.7, green: 0.0, blue: 0.45),  // magenta
        Color(red: 0.35, green: 0.55, blue: 0.0), // olive
    ]
    static func color(_ index: Int) -> Color { colors[index % colors.count] }
}

struct DashboardView: View {
    @Query(sort: \FFTransaction.date, order: .reverse) private var allTransactions: [FFTransaction]
    @Query private var accounts: [FFAccount]
    @Query private var piggyBanks: [FFPiggyBank]
    // Persisted so switching to Transactions/Categories and back keeps the month.
    @AppStorage("dashboardMonth") private var dashboardMonthTS: Double = 0
    // Savings/funding selections are dataset-scoped: demo mode keeps its own,
    // separate from the real selections. The "sample." copy is read in demo mode.
    @AppStorage("useSampleData") private var useSampleData = false
    @AppStorage("savingsAccountIDs") private var savingsRealRaw = ""
    @AppStorage("sample.savingsAccountIDs") private var savingsSampleRaw = ""
    @AppStorage("fundingAccountIDs") private var fundingRealRaw = ""
    @AppStorage("sample.fundingAccountIDs") private var fundingSampleRaw = ""
    private var savingsAccountIDsRaw: String { useSampleData ? savingsSampleRaw : savingsRealRaw }
    private var fundingAccountIDsRaw: String { useSampleData ? fundingSampleRaw : fundingRealRaw }
    @AppStorage("externalMonthlySavings") private var externalSavingsReal = 0.0
    @AppStorage("sample.externalMonthlySavings") private var externalSavingsSample = 0.0
    private var externalMonthlySavings: Double { useSampleData ? externalSavingsSample : externalSavingsReal }
    // Clicking a trend bar jumps to Categories focused on that month.
    @AppStorage("selectedSection") private var selectedSection = Section.dashboard.rawValue
    @AppStorage("categoriesMonth") private var categoriesMonthTS = 0.0
    // One time range, picked at the top and shared by every card below.
    @AppStorage("flowRange") private var rangeRaw = FlowRange.month.rawValue
    // Custom range bounds (timeIntervalSinceReferenceDate; 0 = not set yet).
    @AppStorage("flowCustomStart") private var customStartRaw = 0.0
    @AppStorage("flowCustomEnd") private var customEndRaw = 0.0
    // Live toggle: spread "spreadN"-tagged lump sums across N months. Lives on
    // the dashboard (not Settings) so it can be flipped while watching the cards.
    @AppStorage("amortizeView") private var amortizeView = false
    // A frozen snapshot of "how much the piggy-bank plan needed, and how much
    // was already saved toward it" taken once per pay period — see
    // `piggyPeriodProgress()` below for why this exists instead of just
    // re-running `piggyNeed` fresh every time.
    @AppStorage("piggyPeriodSnapshot") private var piggyPeriodSnapshotReal = ""
    @AppStorage("sample.piggyPeriodSnapshot") private var piggyPeriodSnapshotSample = ""
    private var piggyPeriodSnapshotRaw: String {
        get { useSampleData ? piggyPeriodSnapshotSample : piggyPeriodSnapshotReal }
        nonmutating set { if useSampleData { piggyPeriodSnapshotSample = newValue } else { piggyPeriodSnapshotReal = newValue } }
    }

    private var transactions: [FFTransaction] {
        Insights.entries(allTransactions, amortize: amortizeView)
    }

    private var range: FlowRange { FlowRange(rawValue: rangeRaw) ?? .month }

    private var selectedMonth: Date {
        dashboardMonthTS == 0 ? Insights.monthStart(Date()) : Date(timeIntervalSince1970: dashboardMonthTS)
    }

    /// Inclusive custom bounds, defaulting to "25th of last month → today" —
    /// a salary-to-salary window.
    private var customStart: Date {
        get {
            if customStartRaw > 0 { return Date(timeIntervalSinceReferenceDate: customStartRaw) }
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Insights.monthStart(Date()))!
            return Calendar.current.date(byAdding: .day, value: 24, to: lastMonth)!
        }
        nonmutating set { customStartRaw = newValue.timeIntervalSinceReferenceDate }
    }
    private var customEnd: Date {
        get { customEndRaw > 0 ? Date(timeIntervalSinceReferenceDate: customEndRaw) : Date() }
        nonmutating set { customEndRaw = newValue.timeIntervalSinceReferenceDate }
    }

    // MARK: Piggy-bank period progress
    //
    // `Insights.piggyNeed` caps each piggy's contribution at ITS OWN share of
    // the current pay period — so if the total shown is "€1,600 still needed"
    // and the user adds exactly €1,600 across their piggy banks but NOT in
    // the same split the breakdown implied (e.g. more into one goal, less
    // into another), a fresh per-piggy recompute would still show some
    // amount left over: overfunding one goal beyond its own period share
    // doesn't carry over to reduce another goal's need. That's not what
    // "still needed this period" should mean — the total is meant to be
    // fungible. Fix: freeze a snapshot once per pay period of (a) the total
    // needed and (b) the total left-to-save across every tracked piggy, then
    // track progress as the DROP in that aggregate total, however it's
    // distributed. `stillNeeded` reaches exactly 0 once total contributions
    // (in any split) match the frozen target.
    // Per-piggy pay-period progress tracking (and its shared `commitment`
    // computation) lives in `PiggyProgress` — shared with the menu-bar
    // widget, the HTML export, and PiggyBanksView's "Mark as paid this
    // period" action, so all four surfaces always agree. See its doc comment
    // for why progress has to be frozen per-piggy instead of re-derived
    // fresh on every render.

    // MARK: Per-render state
    //
    // `window`, `essentialProjection`, `piggyCommitment` etc. all scan/group
    // the (potentially years-long, real) transaction history, and used to be
    // plain uncached computed properties referenced from several places in
    // `body` (directly and via `savings`) — each access re-derived everything
    // from scratch. On real, multi-year data that redundancy was slow enough
    // to look like a launch hang. `DashState` computes the whole chain once
    // per render; `body` builds one and threads it through as plain data
    // (mirrors the same fix applied to `BudgetsView`).
    private struct DashState {
        let transactions: [FFTransaction]
        let window: (start: Date, end: Date)
        let windowIncludesToday: Bool
        let recentTimeframe: Bool
        let hasRecentPaycheck: Bool
        let projectionHorizonEnd: Date
        let essentialProjection: Insights.EssentialProjection?
        let piggyCommitment: (amount: Decimal, mixed: Bool, breakdown: [PiggyProgress.BreakdownItem])?
        let externalCommitment: Decimal?
        let periodInsights: MonthInsights
        let series: [MonthInsights]
        let trendSeries: [MonthInsights]
        let currency: String
        let savings: HeroSavingsCard.Savings?
        let periodLabel: String
    }

    private func makeState() -> DashState {
        let transactions = self.transactions
        let cal = Calendar.current
        let window: (start: Date, end: Date) = {
            switch range {
            case .month:
                let start = Insights.monthStart(selectedMonth)
                return (start, cal.date(byAdding: .month, value: 1, to: start)!)
            case .custom:
                let start = cal.startOfDay(for: customStart)
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd))!
                return (start, max(start, end))
            case .payday:
                // The whole day of the most recent paycheck → end of today. Snap
                // to start-of-day (imported transactions carry no meaningful time).
                let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                if let last = transactions.filter(Insights.isPaycheck).map(\.date).max() {
                    return (cal.startOfDay(for: last), end)
                }
                let start = Insights.monthStart(Date())   // no paycheck detected → this month
                return (start, cal.date(byAdding: .month, value: 1, to: start)!)
            default:
                return range.window
            }
        }()

        let windowIncludesToday = window.start <= Date() && Date() < window.end
        let recentTimeframe = window.start >= cal.date(byAdding: .day, value: -31, to: Date())!
        let hasRecentPaycheck: Bool = {
            let cutoff = cal.date(byAdding: .day, value: -31, to: Date())!
            return transactions.contains { Insights.isPaycheck($0) && $0.date >= cutoff }
        }()

        // The full period end used for essential-spend projection. Payday's
        // own `window` stops at today (that's what Income/Spent report on),
        // so this extends past today to the estimated next paycheck.
        let projectionHorizonEnd: Date = {
            guard range == .payday else { return window.end }
            guard let last = transactions.filter(Insights.isPaycheck).map(\.date).max() else { return window.end }
            return Insights.nextPaycheckEstimate(after: cal.startOfDay(for: last), in: transactions)
        }()

        // How much essential spending is likely still to come before payday —
        // only meaningful for the in-progress Payday window. Other ranges
        // (incl. Month) fall back to the plain income-minus-spend delta
        // instead: a "since I got paid" projection doesn't map onto an
        // arbitrary calendar month.
        let essentialProjection: Insights.EssentialProjection? = (windowIncludesToday && range == .payday)
            ? Insights.essentialProjection(window: (window.start, projectionHorizonEnd),
                                           asOf: Date(), in: allTransactions)
            : nil

        // Days in the projected period (start → payday/month end) — used to
        // scale the flat monthly piggy/external-savings commitments.
        let projectionWindowDays = Double(cal.dateComponents([.day], from: window.start, to: projectionHorizonEnd).day ?? 30)

        // How much needs to go into piggy banks this period — see
        // `PiggyProgress.commitment` for why this is tracked per-piggy
        // against a frozen snapshot rather than freshly recomputed every
        // time (long-horizon goals barely move a fresh "share" calculation
        // even right after being fully paid for the period, so progress has
        // to be measured against a fixed starting line). Same in-progress-period
        // gate as essentials; excludes anything opted out of in Piggy Banks.
        let piggyCommitment: (amount: Decimal, mixed: Bool, breakdown: [PiggyProgress.BreakdownItem])? = {
            guard windowIncludesToday, range == .payday else { return nil }
            let conv = Insights.converter(for: transactions)
            let result = PiggyProgress.commitment(piggyBanks: piggyBanks,
                                                  window: (window.start, projectionHorizonEnd),
                                                  rawSnapshot: piggyPeriodSnapshotRaw, converter: conv)
            if result.rawSnapshot != piggyPeriodSnapshotRaw { piggyPeriodSnapshotRaw = result.rawSnapshot }
            guard let c = result.commitment else { return nil }
            return (c.amount, c.mixed, c.breakdown)
        }()

        // A flat monthly amount saved outside Firefly (Settings), scaled to this period.
        let externalCommitment: Decimal? = {
            guard windowIncludesToday, range == .payday, externalMonthlySavings > 0 else { return nil }
            return Decimal(externalMonthlySavings) * Decimal(projectionWindowDays / 30.4)
        }()

        let periodInsights = Insights.range(start: window.start, end: window.end, in: transactions)
        let series = Insights.monthlySeries(count: 12, in: transactions)

        // The trend chart follows the selected range; short scopes
        // (Month/Custom) keep a 12-month context so the chart stays meaningful.
        let trendCount: Int = {
            switch range {
            case .month, .custom, .year, .ytd, .qtd, .payday: return 12
            case .threeMonths: return 3
            case .sixMonths: return 6
            case .fiveYears: return 60
            case .all:
                let earliest = transactions.map(\.date).min() ?? Date()
                let diff = cal.dateComponents(
                    [.month], from: Insights.monthStart(earliest), to: Insights.monthStart(Date())).month ?? 0
                return diff + 1
            }
        }()
        let trendSeries = Insights.monthlySeries(count: trendCount, in: transactions)

        let currency = Insights.baseCurrency(transactions)

        // "Saved so far" KPI: balances of the user's savings accounts plus
        // piggy-bank fulfilment, everything in the base currency.
        let savings: HeroSavingsCard.Savings? = {
            let savingsSel = Set(savingsAccountIDsRaw.split(separator: "\n").map(String.init))
            let fundingSel = Set(fundingAccountIDsRaw.split(separator: "\n").map(String.init))
            let selected = accounts.filter { savingsSel.contains($0.accountID) }
            let funding = accounts.filter { fundingSel.contains($0.accountID) }
            guard !selected.isEmpty || !funding.isEmpty || !piggyBanks.isEmpty else { return nil }
            let conv = Insights.converter(for: transactions)

            func total(_ list: [FFAccount]) -> (amount: Decimal, mixed: Bool) {
                var sum: Decimal = 0
                var mixed = false
                for account in list {
                    let (v, converted) = conv.convert(account.currentBalance, from: account.currencyCode)
                    sum += v
                    if converted { mixed = true }
                }
                return (sum, mixed)
            }

            let saved = total(selected)
            // A "Savings account" is already the user's own declaration that
            // an account's money is allocated (it's exactly what feeds
            // "Saved so far" above) — so if the SAME account is also picked
            // as a funding account, its balance shouldn't be double-counted
            // as free to allocate here too. Simpler and more robust than
            // inferring allocation from piggy-account linkage: it holds
            // regardless of whether every piggy bothers to record an
            // `accountID`, and matches "Saved so far"'s own definition of
            // "allocated" exactly.
            let rawAvailable = total(funding.filter { !savingsSel.contains($0.accountID) })
            // Idle cash overstates what's truly free: net out essentials still
            // due and piggy contributions still needed this period, so this
            // trends toward zero as money gets allocated rather than sitting
            // unassigned. Not netted against `saved`/piggy totals above —
            // those are separate, point-in-time balances, not commitments.
            let committed = (essentialProjection?.expectedRemaining ?? 0)
                + (piggyCommitment?.amount ?? 0) + (externalCommitment ?? 0)
            let available = (amount: rawAvailable.amount - committed,
                             mixed: rawAvailable.mixed || (essentialProjection?.mixed ?? false)
                                 || (piggyCommitment?.mixed ?? false))
            var current: Decimal = 0
            var target: Decimal = 0
            var piggyMixed = false
            for piggy in piggyBanks {
                let (c, convertedC) = conv.convert(piggy.currentAmount, from: piggy.currencyCode)
                let (t, convertedT) = conv.convert(piggy.targetAmount, from: piggy.currencyCode)
                current += c
                target += t
                if convertedC || convertedT { piggyMixed = true }
            }
            return .init(saved: selected.isEmpty ? nil : saved.amount, savedMixed: saved.mixed,
                         available: funding.isEmpty ? nil : available.amount, availableMixed: available.mixed,
                         piggyCurrent: current, piggyTarget: target, piggyMixed: piggyMixed)
        }()

        let periodLabel: String = {
            if range == .all { return "All time" }
            if range == .payday {
                return "Since \(window.start.formatted(.dateTime.month(.abbreviated).day()))"
            }
            let lastDay = cal.date(byAdding: .day, value: -1, to: window.end)!
            return "\(window.start.formatted(.dateTime.month(.abbreviated).year())) – \(lastDay.formatted(.dateTime.month(.abbreviated).year()))"
        }()

        return DashState(transactions: transactions, window: window, windowIncludesToday: windowIncludesToday,
                          recentTimeframe: recentTimeframe, hasRecentPaycheck: hasRecentPaycheck,
                          projectionHorizonEnd: projectionHorizonEnd, essentialProjection: essentialProjection,
                          piggyCommitment: piggyCommitment, externalCommitment: externalCommitment,
                          periodInsights: periodInsights, series: series, trendSeries: trendSeries,
                          currency: currency, savings: savings, periodLabel: periodLabel)
    }

    var body: some View {
        let state = makeState()
        return ScrollView {
            VStack(spacing: 20) {
                headerBar(periodLabel: state.periodLabel)

                if state.transactions.isEmpty {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "flame",
                        description: Text("Open Settings (⌘,) to configure your Firefly server, then press ⌘R to sync."))
                        .padding(.top, 80)
                } else {
                    HeroSavingsCard(insights: state.periodInsights, series: state.series, currency: state.currency,
                                    monthScope: range == .month, savings: state.savings,
                                    windowIncludesToday: state.windowIncludesToday,
                                    recentTimeframe: state.recentTimeframe,
                                    hasRecentPaycheck: state.hasRecentPaycheck,
                                    essentialProjection: state.essentialProjection,
                                    piggyCommitment: state.piggyCommitment,
                                    externalCommitment: state.externalCommitment,
                                    periodEndLabel: range == .payday
                                        ? "payday on \(state.projectionHorizonEnd.formatted(.dateTime.month(.abbreviated).day()))"
                                        : "month end",
                                    onShowBills: { selectedSection = Section.budgets.rawValue },
                                    onShowPiggyBanks: { selectedSection = Section.piggyBanks.rawValue })
                    SankeyCard(insights: state.periodInsights,
                               transactions: state.transactions,
                               window: state.window,
                               currency: state.currency)
                    HStack(alignment: .top, spacing: 20) {
                        CategoryDonutCard(insights: state.periodInsights, currency: state.currency)
                        TrendCard(series: state.trendSeries, currency: state.currency,
                                  title: range == .all
                                      ? "Spending — all time"
                                      : "Spending — last \(state.trendSeries.count) months",
                                  onSelectMonth: { month in
                                      categoriesMonthTS = month.timeIntervalSinceReferenceDate
                                      selectedSection = Section.categories.rawValue
                                  })
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Dashboard")
    }

    /// Time scope for the whole dashboard: the range picker plus whatever
    /// controls the chosen range needs (month chevrons, custom date pickers).
    private func headerBar(periodLabel: String) -> some View {
        HStack(spacing: 12) {
            switch range {
            case .month:
                monthPicker
            case .custom:
                customPickers
            default:
                Text(periodLabel)
                    .appFont(.title3, weight: .semibold)
            }
            Spacer()
            Toggle(isOn: $amortizeView.animation(.snappy)) {
                Label("Amortise", systemImage: "calendar.badge.clock")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("Amortise: spread transactions tagged spreadN (e.g. an annual insurance tagged spread12) evenly across N months, instead of counting the whole lump in the month it was paid. Shared with Averages.")
            Picker("", selection: $rangeRaw) {
                ForEach(FlowRange.allCases) { r in Text(r.rawValue).tag(r.rawValue) }
            }
            .pickerStyle(.segmented)
            .frame(width: 540)
        }
        .animation(.snappy, value: rangeRaw)
    }

    private var monthPicker: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                .appFont(.title3, weight: .semibold)
                .frame(minWidth: 180)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Insights.monthStart(Date()) <= selectedMonth)
            Button("This month") {
                withAnimation(.snappy) { dashboardMonthTS = 0 }
            }
            .disabled(selectedMonth == Insights.monthStart(Date()))
        }
        .buttonStyle(.borderless)
    }

    private var customPickers: some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: Binding(get: { customStart },
                                                  set: { customStart = $0 }),
                       displayedComponents: .date)
            DatePicker("to", selection: Binding(get: { customEnd },
                                                set: { customEnd = $0 }),
                       in: customStart...,
                       displayedComponents: .date)
        }
        .datePickerStyle(.compact)
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation(.snappy) {
            let next = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth)!
            dashboardMonthTS = next == Insights.monthStart(Date()) ? 0 : next.timeIntervalSince1970
        }
    }
}

// MARK: - Hero: "How much can we save this month?"

struct HeroSavingsCard: View {
    /// "Saved so far" KPI inputs (base currency).
    struct Savings {
        /// nil = no savings accounts selected in Settings (piggy ring only).
        let saved: Decimal?
        let savedMixed: Bool
        /// nil = no funding accounts selected. Combined balance you could move
        /// into your piggy banks right now.
        let available: Decimal?
        let availableMixed: Bool
        let piggyCurrent: Decimal
        let piggyTarget: Decimal
        let piggyMixed: Bool

        var fulfilment: Double? {
            guard piggyTarget > 0 else { return nil }
            return (piggyCurrent / piggyTarget).doubleValue
        }
    }

    let insights: MonthInsights
    let series: [MonthInsights]
    let currency: String
    /// Current/selected month gets forward-looking wording; past windows don't.
    var monthScope = true
    var savings: Savings? = nil
    /// The shown window still includes today (saving is still possible).
    var windowIncludesToday = false
    /// The window is a recent, short one (within the last 31 days).
    var recentTimeframe = false
    /// A paycheck landed in the last 31 days.
    var hasRecentPaycheck = false
    /// Essential spend likely still to come before the period ends (nil when
    /// not applicable — e.g. a past period, or a non-Month/Payday range).
    var essentialProjection: Insights.EssentialProjection? = nil
    /// What still needs to go into piggy banks this period (nil when not applicable).
    var piggyCommitment: (amount: Decimal, mixed: Bool, breakdown: [PiggyProgress.BreakdownItem])? = nil
    /// A flat external (non-Firefly) monthly savings amount, scaled to this period.
    var externalCommitment: Decimal? = nil
    /// "payday on 25 Jul" / "month end" — used in the projection caption.
    var periodEndLabel = ""
    /// Jump to Budgets to see the itemised recurring-bill list.
    var onShowBills: (() -> Void)? = nil
    /// Jump to Piggy Banks to see the per-goal breakdown.
    var onShowPiggyBanks: (() -> Void)? = nil

    private var averageSurplus: Decimal {
        Insights.average(series.dropLast().map(\.surplus))
    }

    /// Bright red so a negative rolling surplus stands out on the dark card.
    private let alertRed = Color(red: 1.0, green: 0.42, blue: 0.42)

    private var essentialRemaining: Decimal { essentialProjection?.expectedRemaining ?? 0 }
    private var piggyAmount: Decimal { piggyCommitment?.amount ?? 0 }
    private var externalAmount: Decimal { externalCommitment ?? 0 }
    private var totalCommitment: Decimal { essentialRemaining + piggyAmount + externalAmount }

    /// Once known essentials, piggy-bank goals, and external savings still to
    /// come are subtracted, this is the realistic end-of-period surplus. Falls
    /// back to the raw surplus when there's nothing to project.
    private var displaySurplus: Decimal {
        insights.surplus - totalCommitment
    }

    private var isProjected: Bool {
        windowIncludesToday && totalCommitment > 0
    }

    private var displayMixed: Bool {
        insights.mixed || (essentialProjection?.mixed ?? false) || (piggyCommitment?.mixed ?? false)
    }

    private var heading: String {
        if isProjected {
            return displaySurplus > 0 ? "From the last paycheck you can safely save or spend up to" : "You're projected to be over by"
        }
        if windowIncludesToday && insights.surplus > 0 { return "You can save up to" }
        if insights.surplus < 0 && recentTimeframe && hasRecentPaycheck {
            return "You cannot save anything at this time"
        }
        return monthScope
            ? (insights.surplus >= 0 ? "You can save" : "You are over by")
            : (insights.surplus >= 0 ? "You saved" : "You overspent by")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading)
                    .appFont(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                Text(abs(displaySurplus).currency(currency, approx: displayMixed))
                    .appFont(size: 56, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                HStack(spacing: 16) {
                    statPill("Income", insights.income, "arrow.down.circle.fill", approx: insights.mixed)
                    statPill("Spent", insights.spent, "arrow.up.circle.fill", approx: insights.mixed)
                    statPill("12-mo avg surplus", averageSurplus, "chart.line.uptrend.xyaxis",
                             valueColor: averageSurplus < 0 ? alertRed : nil)
                }
                .padding(.top, 4)
                if totalCommitment > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        if essentialRemaining > 0 {
                            commitmentRow(icon: "calendar.badge.clock",
                                          text: "\(essentialRemaining.currency(currency, approx: essentialProjection?.mixed ?? false)) of essentials still due before \(periodEndLabel)",
                                          action: onShowBills)
                        }
                        if piggyAmount > 0 {
                            commitmentRow(icon: "banknote.fill",
                                          text: "\(piggyAmount.currency(currency, approx: piggyCommitment?.mixed ?? false)) still needed for piggy banks this period",
                                          action: onShowPiggyBanks)
                            piggyBreakdownRows
                        }
                        if externalAmount > 0 {
                            commitmentRow(icon: "lock.fill",
                                          text: "\(externalAmount.currency(currency)) set aside externally this period",
                                          action: nil)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if let savings {
                savingsPanel(savings)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: displaySurplus >= 0
                    ? [Color(red: 0.05, green: 0.45, blue: 0.35), Color(red: 0.02, green: 0.25, blue: 0.30)]
                    : [Color(red: 0.55, green: 0.15, blue: 0.15), Color(red: 0.30, green: 0.05, blue: 0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20))
    }

    /// "Saved so far" with a joyful piggy ring showing goal fulfilment.
    private func savingsPanel(_ savings: Savings) -> some View {
        HStack(spacing: 18) {
            if let fulfilment = savings.fulfilment {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: min(fulfilment, 1))
                        .stroke(
                            AngularGradient(colors: [Color(red: 1.0, green: 0.71, blue: 0.24),
                                                     Color(red: 0.55, green: 0.95, blue: 0.55)],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360 * min(fulfilment, 1))),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(fulfilment >= 1 ? "🎉" : "🐷")
                            .appFont(size: 30)
                        Text(fulfilment.formatted(.percent.precision(.fractionLength(0))))
                            .appFont(.caption, weight: .bold)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
                .scaledFrame(92)
                .help("Piggy banks: \(savings.piggyCurrent.currency(currency, approx: savings.piggyMixed)) of \(savings.piggyTarget.currency(currency, approx: savings.piggyMixed))")
            }
            VStack(alignment: .trailing, spacing: 2) {
                if let saved = savings.saved {
                    Text("Saved so far")
                        .appFont(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(saved.currency(currency, approx: savings.savedMixed))
                        .appFont(size: 30, weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                if savings.fulfilment != nil {
                    Text("\(savings.piggyCurrent.currency(currency, approx: savings.piggyMixed)) of \(savings.piggyTarget.currency(currency, approx: savings.piggyMixed)) piggy goals")
                        .appFont(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                if let available = savings.available {
                    HStack(spacing: 5) {
                        Image(systemName: "banknote.fill")
                            .foregroundStyle(.white)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Unallocated funds")
                                .appFont(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                            Text(available.currency(currency, approx: savings.availableMixed))
                                .appFont(.callout, weight: .semibold)
                                .foregroundStyle(available < 0 ? alertRed : .white)
                                .contentTransition(.numericText())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                    .padding(.top, savings.saved != nil || savings.fulfilment != nil ? 6 : 0)
                    .help("Your funding accounts' balance, minus essentials and piggy-bank contributions still due this period — what's genuinely free to move or spend, not just idle cash. Trending toward zero means your money is fully put to work.")
                }
            }
        }
    }

    /// Splits the piggy commitment total by destination account (or object
    /// group, for piggies Firefly hasn't linked to an account) — so the
    /// aggregate figure above can be divided up into actual transfers.
    @ViewBuilder
    private var piggyBreakdownRows: some View {
        if let items = piggyCommitment?.breakdown {
            ForEach(items, id: \.key) { item in
                HStack(spacing: 8) {
                    Text("→").opacity(0.5)
                    Text(item.key)
                    Text("·").opacity(0.4)
                    Text(item.amount.currency(currency, approx: item.mixed)).fontWeight(.medium)
                }
                .appFont(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 26)
                .padding(.top, 2)
            }
        }
    }

    /// One "still committed this period" line — tappable when an action is given.
    @ViewBuilder
    private func commitmentRow(icon: String, text: String, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .appFont(.callout)
        .foregroundStyle(.white.opacity(0.8))
        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private func statPill(_ label: String, _ value: Decimal, _ icon: String,
                          approx: Bool = false, valueColor: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).appFont(.caption2)
                Text(value.currency(currency, approx: approx))
                    .appFont(.callout, weight: valueColor == nil ? .semibold : .bold)
                    .foregroundStyle(valueColor ?? .white.opacity(0.9))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.12), in: Capsule())
    }
}

// MARK: - Sankey: income sources → Income → categories + Saved

struct SankeyNode: Identifiable {
    let id = UUID()
    let label: String
    let amount: Decimal
    let color: Color
    /// True when the amount combines more than one currency (shown as ≈).
    var mixed = false
    /// Subcategories ("Main:Sub" convention). Empty = flows straight to the far column.
    var children: [SankeyNode] = []
}

enum FlowRange: String, CaseIterable, Identifiable {
    case month = "Month"
    /// Since the most recent paycheck (data-dependent; the dashboard computes it).
    case payday = "Payday"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case ytd = "YTD"
    case qtd = "QTD"
    case year = "1Y"
    case fiveYears = "5Y"
    case all = "All"
    /// Free start–end dates; only offered on the dashboard Cashflow card.
    case custom = "Custom"
    var id: String { rawValue }

    /// Months back from the end of the current month; nil = all time or an
    /// anchored (year/quarter-to-date / payday) window.
    var monthsBack: Int? {
        switch self {
        case .month: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .year: 12
        case .fiveYears: 60
        case .all, .custom, .ytd, .qtd, .payday: nil
        }
    }

    /// Date window ending after the current month ("Month" anchors to now;
    /// the dashboard overrides it with its selected month). YTD/QTD anchor to
    /// the start of the calendar year / quarter and include the current month.
    var window: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .month, value: 1, to: Insights.monthStart(now))!
        let start: Date
        switch self {
        case .ytd:
            start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1))!
        case .qtd:
            let quarterStartMonth = ((cal.component(.month, from: now) - 1) / 3) * 3 + 1
            start = cal.date(from: DateComponents(year: cal.component(.year, from: now),
                                                  month: quarterStartMonth, day: 1))!
        case .payday:
            // Data-dependent; the dashboard computes the real window. This is a
            // safe current-month fallback for any non-dashboard caller.
            start = Insights.monthStart(now)
        default:
            start = monthsBack.map { cal.date(byAdding: .month, value: -$0, to: end)! } ?? .distantPast
        }
        return (start, end)
    }
}

struct SankeyCard: View {
    let insights: MonthInsights   // already filtered to the dashboard's window
    let transactions: [FFTransaction]
    let window: (start: Date, end: Date)
    let currency: String
    @AppStorage("subThresholdPercent") private var subThresholdPercent = 2.0

    /// Left side: income grouped by its Firefly category (Sure-style), top 5 + Other.
    private var sources: [SankeyNode] {
        let (start, end) = window
        let conv = Insights.converter(for: transactions)
        let incomes = transactions.filter { $0.isIncome && $0.date >= start && $0.date < end }
        var byCategory: [String: Decimal] = [:]
        var mixedCategories: Set<String> = []
        for t in incomes {
            let label = t.categoryName ?? "Uncategorized"
            let (v, converted) = conv.value(t)
            byCategory[label, default: 0] += v
            if converted { mixedCategories.insert(label) }
        }
        let sorted = byCategory.sorted { $0.value > $1.value }
        var nodes = sorted.prefix(5).enumerated().map { i, e in
            SankeyNode(label: e.key, amount: e.value,
                       color: CategoryStyle.color(e.key),
                       mixed: mixedCategories.contains(e.key))
        }
        let other = sorted.dropFirst(5).reduce(Decimal(0)) { $0 + $1.value }
        if other > 0 {
            let otherMixed = sorted.dropFirst(5).contains { mixedCategories.contains($0.key) }
            nodes.append(SankeyNode(label: "Other income", amount: other, color: .gray, mixed: otherMixed))
        }
        return nodes
    }

    /// Right side: main expense categories (grouped from "Main:Sub"), with
    /// subcategories as children flowing to the far column. Plus Surplus in green.
    private var destinations: [SankeyNode] {
        let f = insights

        // Group full category names into main → [(sub, amount, mixed)]
        var mains: [String: [(sub: String?, amount: Decimal, mixed: Bool)]] = [:]
        for c in f.byCategory {
            let (main, sub) = Insights.splitCategory(c.category)
            mains[main, default: []].append((sub, c.amount, f.byCategoryMixed.contains(c.category)))
        }
        let sorted = mains
            .map { (main: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }, entries: $0.value) }
            .sorted { $0.total > $1.total }

        var nodes: [SankeyNode] = []
        var colorIndex = 5
        for entry in sorted.prefix(7) {
            let hasSubs = entry.entries.contains { $0.sub != nil }
            let entryMixed = entry.entries.contains { $0.mixed }
            var children: [SankeyNode] = []
            if hasSubs {
                // Keep the chart readable: a subcategory earns its own node only
                // if it reaches the user-set share of the period's spending
                // (Settings → Cashflow chart, default 2%, max 4 per main);
                // everything smaller rolls into that main's "Other".
                let threshold = f.spent * Decimal(subThresholdPercent / 100)
                let subsSorted = entry.entries
                    .map { (label: $0.sub ?? "General", amount: $0.amount, mixed: $0.mixed) }
                    .sorted { $0.amount > $1.amount }
                let big = subsSorted.prefix(4).filter { $0.amount >= threshold }
                children = big.map { s in
                    colorIndex += 1
                    return SankeyNode(label: s.label, amount: s.amount,
                                      color: Palette.color(colorIndex), mixed: s.mixed)
                }
                let rest = entry.total - big.reduce(Decimal(0)) { $0 + $1.amount }
                if rest > 0 {
                    // If nothing cleared the threshold, skip children entirely —
                    // the main flows straight to the far column as one block.
                    if children.isEmpty {
                        children = []
                    } else {
                        let restMixed = subsSorted.dropFirst(big.count).contains { $0.mixed }
                        children.append(SankeyNode(label: "Other", amount: rest, color: .gray, mixed: restMixed))
                    }
                }
            }
            colorIndex += 1
            nodes.append(SankeyNode(label: entry.main, amount: entry.total,
                                    color: CategoryStyle.color(entry.main), mixed: entryMixed,
                                    children: children))
        }
        let other = sorted.dropFirst(7).reduce(Decimal(0)) { $0 + $1.total }
        if other > 0 {
            let otherMixed = sorted.dropFirst(7).contains { $0.entries.contains { $0.mixed } }
            nodes.append(SankeyNode(label: "Other", amount: other, color: .gray, mixed: otherMixed))
        }
        if f.surplus > 0 {
            nodes.append(SankeyNode(label: "Surplus", amount: f.surplus, color: .green, mixed: f.mixed))
        }
        return nodes
    }

    var body: some View {
        Card(title: "Cashflow", icon: "arrow.triangle.branch") {
            if insights.income > 0 || insights.spent > 0 {
                let dests = destinations
                // Reserve ~26pt per far-column node for its single-line label;
                // grow the chart instead of letting labels spill out of the card.
                let farCount = dests.reduce(0) { $0 + max($1.children.count, 1) }
                let groupGaps = CGFloat(max(dests.count - 1, 0)) * 16
                let height = max(320, CGFloat(max(farCount, sources.count)) * 26 + groupGaps)
                SankeyDiagram(sources: sources, destinations: dests,
                              centerLabel: "Cash Flow", centerAmount: insights.income,
                              centerApprox: insights.mixed,
                              currency: currency)
                    .frame(height: height)
                    .clipped()
                    .animation(.snappy, value: window.start)
                    .animation(.snappy, value: window.end)
            } else {
                Text("No transactions in this period.").foregroundStyle(.secondary)
            }
        }
    }
}


/// Multi-stage Sankey: income categories → "Cash Flow" spine → main categories
/// → subcategories (Sure style). Mains without subcategories flow straight to
/// the far right. Labels are collision-resolved so small adjacent nodes never overlap.
struct SankeyDiagram: View {
    let sources: [SankeyNode]
    let destinations: [SankeyNode]
    var centerLabel = "Cash Flow"
    var centerAmount: Decimal = 0
    var centerApprox = false
    let currency: String

    private let blockWidth: CGFloat = 10
    private let gap: CGFloat = 8
    private let groupGap: CGFloat = 16
    private let labelWidth: CGFloat = 150
    // Single-line labels ("Name  €123") — half the height of the old two-line
    // style, so more nodes fit vertically without their labels overlapping.
    private let labelHeight: CGFloat = 18

    /// Far-right column: subcategories of mains that have them, otherwise the main itself.
    private var farNodes: [SankeyNode] {
        destinations.flatMap { $0.children.isEmpty ? [$0] : $0.children }
    }

    /// Destinations that draw a visible block in the middle column.
    private var visibleMidIndices: [Int] {
        destinations.indices.filter { !destinations[$0].children.isEmpty }
    }

    /// Far-column indices where a new parent's run starts — an extra gap is
    /// inserted there so each main's subcategories read as one group.
    private var farGroupBreaks: Set<Int> {
        var breaks: Set<Int> = []
        var index = 0
        for dest in destinations {
            if index > 0 { breaks.insert(index) }
            index += max(dest.children.count, 1)
        }
        return breaks
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let leftX = labelWidth
            let farX = geo.size.width - labelWidth - blockWidth
            let spineX = leftX + (farX - leftX) * 0.34
            let midColX = leftX + (farX - leftX) * 0.67

            let leftTotal = sources.reduce(Decimal(0)) { $0 + $1.amount }
            let farTotal = farNodes.reduce(Decimal(0)) { $0 + $1.amount }
            let grandTotal = max(leftTotal, farTotal)

            let leftRects = layout(nodes: sources, total: grandTotal, height: height)
            let farRects = layout(nodes: farNodes, total: grandTotal, height: height,
                                  breakBefore: farGroupBreaks)
            // Every destination gets a mid-column slot in spine order — childless
            // mains pass through an invisible waypoint there, so ribbons keep a
            // consistent vertical order at every column and can never cross.
            let midRects = layout(nodes: destinations, total: grandTotal, height: height)

            let centerHeight = usable(height) * frac(min(leftTotal, grandTotal), grandTotal)
            let centerY = (height - centerHeight) / 2

            let leftLabelYs = resolveLabels(leftRects.map(\.midY), height: height)
            let farLabelYs = resolveLabels(farRects.map(\.midY), height: height)
            // Re-centre each source block on its (collision-resolved) label so a
            // tiny block and its spread-out label stay together — otherwise small
            // incomes bunch up while their labels fan out, and the two no longer
            // line up with the ribbon that joins them.
            let leftBlockRects = leftRects.enumerated().map { i, r in
                CGRect(x: r.minX, y: leftLabelYs[i] - r.height / 2, width: r.width, height: r.height)
            }

            ZStack(alignment: .topLeading) {
                // Ribbons: sources → spine
                ribbonStack(fromRects: leftBlockRects, nodes: sources,
                            fromX: leftX + blockWidth, toX: spineX,
                            targetY: centerY, targetHeight: centerHeight, total: leftTotal)

                // Ribbons: spine → mid column → far column
                destinationRibbons(spineX: spineX + blockWidth, midColX: midColX, farX: farX,
                                   centerY: centerY, centerHeight: centerHeight,
                                   midRects: midRects, farRects: farRects)

                // Source blocks + labels
                ForEach(Array(sources.enumerated()), id: \.element.id) { i, node in
                    let rect = leftBlockRects[i]
                    block(node, height: rect.height).offset(x: leftX, y: rect.minY)
                    nodeLabel(node, alignment: .trailing)
                        .frame(width: labelWidth - 8, alignment: .trailing)
                        .offset(x: 0, y: leftLabelYs[i] - labelHeight / 2)
                }

                // Centre spine + label
                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.85))
                    .frame(width: blockWidth, height: max(centerHeight, 3))
                    .offset(x: spineX, y: centerY)
                    .help("\(centerLabel): \(centerAmount.currency(currency))")
                VStack(alignment: .trailing, spacing: 0) {
                    Text(centerLabel).appFont(.caption, weight: .semibold)
                    Text(centerAmount.currency(currency, approx: centerApprox))
                        .appFont(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(width: 100, alignment: .trailing)
                .offset(x: spineX - 106, y: centerY + centerHeight / 2 - labelHeight / 2)

                // Mid main-category blocks + labels (only mains with subcategories)
                let visibleMids = visibleMidIndices
                let midLabelYs = resolveLabels(visibleMids.map { midRects[$0].midY }, height: height)
                ForEach(visibleMids.indices, id: \.self) { k in
                    let node = destinations[visibleMids[k]]
                    let rect = midRects[visibleMids[k]]
                    block(node, height: rect.height).offset(x: midColX, y: rect.minY)
                    nodeLabel(node, alignment: .trailing)
                        .frame(width: 140, alignment: .trailing)
                        .offset(x: midColX - 146, y: midLabelYs[k] - labelHeight / 2)
                }

                // Far column blocks + labels
                ForEach(Array(farNodes.enumerated()), id: \.element.id) { i, node in
                    let rect = farRects[i]
                    block(node, height: rect.height).offset(x: farX, y: rect.minY)
                    nodeLabel(node, alignment: .leading)
                        .frame(width: labelWidth - 8, alignment: .leading)
                        .offset(x: farX + blockWidth + 8, y: farLabelYs[i] - labelHeight / 2)
                }
            }
        }
    }

    // MARK: pieces

    private func block(_ node: SankeyNode, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(node.color)
            .frame(width: blockWidth, height: max(height, 3))
            .help("\(node.label): \(node.amount.currency(currency))")
    }

    /// Name and value on ONE line ("Groceries  €191"). The value never
    /// truncates (`fixedSize`); the name shortens first when space is tight.
    /// Column side (leading/trailing) is applied by the caller's frame.
    private func nodeLabel(_ node: SankeyNode, alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 5) {
            Text(node.label)
                .appFont(.caption, weight: .medium)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(node.amount.currency(currency, approx: node.mixed))
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
        }
    }

    private func frac(_ a: Decimal, _ b: Decimal) -> CGFloat {
        CGFloat(a.doubleValue / max(b.doubleValue, 1))
    }

    private func usable(_ height: CGFloat) -> CGFloat {
        height - gap * CGFloat(max(sources.count, farNodes.count) - 1) - 16
    }

    private func layout(nodes: [SankeyNode], total: Decimal, height: CGFloat,
                        breakBefore: Set<Int> = []) -> [CGRect] {
        let extra = groupGap * CGFloat(breakBefore.count)
        let u = usable(height) - extra
        let nodesTotal = nodes.reduce(Decimal(0)) { $0 + $1.amount }
        let blockSum = u * frac(nodesTotal, total)
        var y = (height - blockSum - gap * CGFloat(nodes.count - 1) - extra) / 2
        var rects: [CGRect] = []
        for (i, node) in nodes.enumerated() {
            if breakBefore.contains(i) { y += groupGap }
            let h = max(u * frac(node.amount, total), 3)
            rects.append(CGRect(x: 0, y: y, width: blockWidth, height: h))
            y += h + gap
        }
        return rects
    }

    /// Keep each label anchored to its own block, only nudging neighbours apart
    /// when they would overlap. A downward sweep pushes overlapping labels below
    /// the one above; an upward sweep then pulls the column back inside the
    /// chart. Unlike mean-centred clustering, a big block's label never gets
    /// dragged toward a tiny neighbour's — Rent stays beside Rent.
    private func resolveLabels(_ desired: [CGFloat], height: CGFloat) -> [CGFloat] {
        guard desired.count > 1 else { return desired }
        var ys = desired
        ys[0] = max(ys[0], labelHeight / 2)
        for i in 1..<ys.count {
            ys[i] = max(ys[i], ys[i - 1] + labelHeight)
        }
        ys[ys.count - 1] = min(ys[ys.count - 1], height - labelHeight / 2)
        for i in (0..<(ys.count - 1)).reversed() {
            ys[i] = min(ys[i], ys[i + 1] - labelHeight)
        }
        return ys
    }

    private func ribbon(x0: CGFloat, top0: CGFloat, bot0: CGFloat,
                        x1: CGFloat, top1: CGFloat, bot1: CGFloat) -> Path {
        let cx = (x0 + x1) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: top0))
        path.addCurve(to: CGPoint(x: x1, y: top1),
                      control1: CGPoint(x: cx, y: top0), control2: CGPoint(x: cx, y: top1))
        path.addLine(to: CGPoint(x: x1, y: bot1))
        path.addCurve(to: CGPoint(x: x0, y: bot0),
                      control1: CGPoint(x: cx, y: bot1), control2: CGPoint(x: cx, y: bot0))
        path.closeSubpath()
        return path
    }

    private func gradientFill(_ path: Path, color: Color, fadeRight: Bool) -> some View {
        path.fill(LinearGradient(
            colors: fadeRight
                ? [color.opacity(0.35), color.opacity(0.10)]
                : [color.opacity(0.10), color.opacity(0.35)],
            startPoint: .leading, endPoint: .trailing))
    }

    private func ribbonStack(fromRects: [CGRect], nodes: [SankeyNode],
                             fromX: CGFloat, toX: CGFloat,
                             targetY: CGFloat, targetHeight: CGFloat, total: Decimal) -> some View {
        var sliceY = targetY
        var shapes: [(Path, Color)] = []
        for (node, rect) in zip(nodes, fromRects) {
            let sliceH = targetHeight * frac(node.amount, total)
            shapes.append((ribbon(x0: fromX, top0: rect.minY, bot0: rect.maxY,
                                  x1: toX, top1: sliceY, bot1: sliceY + sliceH), node.color))
            sliceY += sliceH
        }
        return ZStack {
            ForEach(Array(shapes.enumerated()), id: \.offset) { _, s in
                gradientFill(s.0, color: s.1, fadeRight: true)
            }
        }
    }

    /// Ribbon that flows through a mid-column waypoint instead of cutting a
    /// straight diagonal — used by childless destinations so they respect the
    /// same column ordering as everything else.
    private func ribbonThrough(x0: CGFloat, top0: CGFloat, bot0: CGFloat,
                               x1: CGFloat, top1: CGFloat, bot1: CGFloat,
                               x2: CGFloat, top2: CGFloat, bot2: CGFloat) -> Path {
        let cxA = (x0 + x1) / 2
        let cxB = (x1 + x2) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: top0))
        path.addCurve(to: CGPoint(x: x1, y: top1),
                      control1: CGPoint(x: cxA, y: top0), control2: CGPoint(x: cxA, y: top1))
        path.addCurve(to: CGPoint(x: x2, y: top2),
                      control1: CGPoint(x: cxB, y: top1), control2: CGPoint(x: cxB, y: top2))
        path.addLine(to: CGPoint(x: x2, y: bot2))
        path.addCurve(to: CGPoint(x: x1, y: bot1),
                      control1: CGPoint(x: cxB, y: bot2), control2: CGPoint(x: cxB, y: bot1))
        path.addCurve(to: CGPoint(x: x0, y: bot0),
                      control1: CGPoint(x: cxA, y: bot1), control2: CGPoint(x: cxA, y: bot0))
        path.closeSubpath()
        return path
    }

    /// All ribbons right of the spine. Mains with subcategories: spine → mid
    /// block, then one ribbon per child to the far column. Childless mains:
    /// a single smooth ribbon spine → (mid waypoint) → far block.
    private func destinationRibbons(spineX: CGFloat, midColX: CGFloat, farX: CGFloat,
                                    centerY: CGFloat, centerHeight: CGFloat,
                                    midRects: [CGRect], farRects: [CGRect]) -> some View {
        let total = destinations.reduce(Decimal(0)) { $0 + $1.amount }
        var sliceY = centerY
        var farIndex = 0
        var shapes: [(Path, Color)] = []
        for (i, dest) in destinations.enumerated() {
            let sliceH = centerHeight * frac(dest.amount, total)
            let midRect = midRects[i]
            if dest.children.isEmpty {
                let far = farRects[farIndex]; farIndex += 1
                shapes.append((ribbonThrough(x0: spineX, top0: sliceY, bot0: sliceY + sliceH,
                                             x1: midColX, top1: midRect.minY, bot1: midRect.maxY,
                                             x2: farX, top2: far.minY, bot2: far.maxY), dest.color))
            } else {
                shapes.append((ribbon(x0: spineX, top0: sliceY, bot0: sliceY + sliceH,
                                      x1: midColX, top1: midRect.minY, bot1: midRect.maxY), dest.color))
                var y = midRect.minY
                for child in dest.children {
                    let childRect = farRects[farIndex]; farIndex += 1
                    let h = midRect.height * frac(child.amount, dest.amount)
                    shapes.append((ribbon(x0: midColX + blockWidth, top0: y, bot0: y + h,
                                          x1: farX, top1: childRect.minY, bot1: childRect.maxY), child.color))
                    y += h
                }
            }
            sliceY += sliceH
        }
        return ZStack {
            ForEach(Array(shapes.enumerated()), id: \.offset) { _, s in
                gradientFill(s.0, color: s.1, fadeRight: false)
            }
        }
    }
}

// MARK: - Donut: "Where did the money go?" (the pie chart)

struct CategoryDonutCard: View {
    let insights: MonthInsights
    let currency: String
    @AppStorage("subThresholdPercent") private var subThresholdPercent = 2.0

    private var mains: [Insights.MainEntry] {
        Insights.collapseSmall(
            Insights.mainBreakdown(insights.byCategory, mixedCategories: insights.byCategoryMixed),
            thresholdPercent: subThresholdPercent)
    }

    var body: some View {
        Card(title: "Where did the money go?", icon: "chart.pie.fill") {
            if mains.isEmpty {
                Text("No spending in this period.").foregroundStyle(.secondary)
            } else {
                DonutListChart(
                    slices: mains.map { m in
                        .init(label: m.main, amount: m.amount,
                              color: CategoryStyle.color(m.main),
                              mixed: m.mixed,
                              detail: DonutListChart.subDetail(m.subs, currency: currency))
                    },
                    currency: currency,
                    centerTitle: "Spent",
                    centerAmount: insights.spent,
                    centerApprox: insights.mixed)
                    .frame(height: 360)
                    .animation(.snappy, value: insights.month)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 12-month trend with rolling average

struct TrendCard: View {
    let series: [MonthInsights]
    let currency: String
    var title = "Spending — last 12 months"
    /// Click a bar to drill into that month elsewhere (Categories).
    var onSelectMonth: ((Date) -> Void)? = nil
    @State private var hoveredMonth: Date?

    private var averageSpent: Double {
        Insights.average(series.map(\.spent)).doubleValue
    }

    var body: some View {
        Card(title: title, icon: "chart.bar.fill") {
            Chart {
                ForEach(series, id: \.month) { m in
                    BarMark(
                        x: .value("Month", m.month, unit: .month),
                        y: .value("Spent", m.spent.doubleValue))
                        .foregroundStyle(
                            m.spent.doubleValue > averageSpent
                                ? Color.orange.gradient : Color.teal.gradient)
                        .opacity(hoveredMonth == nil || hoveredMonth == m.month ? 1 : 0.5)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Average", averageSpent))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(Decimal(averageSpent).currency(currency))")
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(2, series.count / 6))) {
                    AxisValueLabel(format: series.count > 12
                                   ? .dateTime.month(.abbreviated).year(.twoDigits)
                                   : .dateTime.month(.abbreviated))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): hoveredMonth = month(at: location, proxy, geo)
                            case .ended: hoveredMonth = nil
                            }
                        }
                        .onTapGesture { location in
                            if let m = month(at: location, proxy, geo) { onSelectMonth?(m) }
                        }
                        .pointerStyle(.link)

                    // Amount label that tracks the hovered bar.
                    if let hoveredMonth, let m = series.first(where: { $0.month == hoveredMonth }),
                       let plot = proxy.plotFrame, let px = proxy.position(forX: hoveredMonth) {
                        Text(m.spent.currency(currency, approx: m.mixed))
                            .appFont(.caption, weight: .semibold).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .position(x: geo[plot].origin.x + px, y: 8)
                    }
                }
            }
            .frame(height: 300)
        }
        .frame(maxWidth: .infinity)
    }

    /// The month whose bar sits under a point in the plot.
    private func month(at location: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) -> Date? {
        guard let plot = proxy.plotFrame else { return nil }
        let x = location.x - geo[plot].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return Insights.monthStart(date)
    }
}

// MARK: - Shared card chrome

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .appFont(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}
