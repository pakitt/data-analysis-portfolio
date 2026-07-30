import SwiftUI
import SwiftData

/// Menu bar glance: the current pay period (since the last paycheck) and how
/// many days remain until the next one is expected.
struct MenuBarView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Query private var allTransactions: [FFTransaction]
    @Query private var piggyBanks: [FFPiggyBank]
    // Shared with Dashboard/Budgets/Averages — read here too so this widget's
    // figures match whatever the Dashboard is currently showing for its
    // Payday range, instead of always using raw (non-amortised) figures.
    @AppStorage("amortizeView") private var amortizeView = false
    @AppStorage("useSampleData") private var useSampleData = false
    @AppStorage("externalMonthlySavings") private var externalSavingsReal = 0.0
    @AppStorage("sample.externalMonthlySavings") private var externalSavingsSample = 0.0
    private var externalMonthlySavings: Double { useSampleData ? externalSavingsSample : externalSavingsReal }

    private var transactions: [FFTransaction] { Insights.entries(allTransactions, amortize: amortizeView) }

    /// Paycheck arrival dates (regular income), oldest first. The keyword and
    /// the regular-cadence start date are both configurable in Settings.
    private var paycheckDates: [Date] {
        transactions
            .filter(Insights.isPaycheck)
            .map(\.date)
            .sorted()
    }

    /// Mean gap between consecutive paychecks; 30 days until two are on record.
    private var averageInterval: Int { Insights.averagePaycheckInterval(transactions) }

    // MARK: Per-render state
    //
    // Mirrors the same fix applied to BudgetsView/DashboardView: everything
    // below (income/spent, and the essentials/piggy/external-savings
    // projection that makes "how much can I actually save" trustworthy) is
    // computed once here rather than via several independent, uncached
    // computed properties that would each re-scan the transaction history.
    private struct MenuState {
        let lastPaycheck: Date?
        let nextPaycheck: Date?
        let daysLeft: Int
        let insights: MonthInsights
        let essentialRemaining: Decimal
        let piggyAmount: Decimal
        let externalAmount: Decimal
        let totalCommitment: Decimal
        let displaySurplus: Decimal
        let displayMixed: Bool
        let currency: String
        let savedLabel: String
        let commitmentCaption: String?
    }

    private func makeState() -> MenuState {
        let cal = Calendar.current
        let last = paycheckDates.last
        // Normalised to start-of-day before estimating, same as Dashboard's
        // `projectionHorizonEnd` — imported transactions occasionally carry a
        // stray non-midnight time, which would otherwise skew the estimate.
        let next = last.map { Insights.nextPaycheckEstimate(after: cal.startOfDay(for: $0), in: transactions) }
        let daysLeft = next.map {
            max(cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: $0)).day ?? 0, 0)
        } ?? 0

        // Figures cover the current pay period: last paycheck → today (inclusive).
        let insights: MonthInsights = {
            guard let last else { return Insights.insights(for: Date(), in: transactions) }
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
            return Insights.range(start: cal.startOfDay(for: last), end: end, in: transactions)
        }()

        // The FULL projected period — last paycheck → the *estimated next
        // one*, not just today — the same horizon Dashboard's Payday
        // essentials/piggy/external projections use, so this widget's
        // headline figure matches Dashboard's instead of overstating what's
        // actually free (raw income-minus-spent ignores bills not yet paid).
        let projectionWindow: (start: Date, end: Date)? = {
            guard let last, let next else { return nil }
            return (cal.startOfDay(for: last), next)
        }()

        let essentialProjection: Insights.EssentialProjection? = projectionWindow.map {
            Insights.essentialProjection(window: $0, asOf: Date(), in: allTransactions)
        }

        // Shares the Dashboard's frozen per-piggy tracking (see PiggyProgress
        // doc comment) so this widget's figure always agrees with it, instead
        // of independently re-deriving a fresh — and possibly stale-looking
        // — total from scratch.
        let piggyCommitment: (amount: Decimal, mixed: Bool)? = projectionWindow.map { w in
            let conv = Insights.converter(for: transactions)
            let key = AppSettings.key("piggyPeriodSnapshot")
            let raw = UserDefaults.standard.string(forKey: key) ?? ""
            let result = PiggyProgress.commitment(piggyBanks: piggyBanks, window: w,
                                                  rawSnapshot: raw, converter: conv)
            if result.rawSnapshot != raw { UserDefaults.standard.set(result.rawSnapshot, forKey: key) }
            return (result.commitment?.amount ?? 0, result.commitment?.mixed ?? false)
        }

        let externalCommitment: Decimal? = {
            guard let w = projectionWindow, externalMonthlySavings > 0 else { return nil }
            let days = Double(cal.dateComponents([.day], from: w.start, to: w.end).day ?? 30)
            return Decimal(externalMonthlySavings) * Decimal(days / 30.4)
        }()

        let essentialRemaining = essentialProjection?.expectedRemaining ?? 0
        let piggyAmount = piggyCommitment?.amount ?? 0
        let externalAmount = externalCommitment ?? 0
        let totalCommitment = essentialRemaining + piggyAmount + externalAmount
        let displaySurplus = insights.surplus - totalCommitment
        let displayMixed = insights.mixed || (essentialProjection?.mixed ?? false) || (piggyCommitment?.mixed ?? false)
        let currency = Insights.baseCurrency(transactions)

        let savedLabel: String = {
            if totalCommitment > 0 { return displaySurplus >= 0 ? "Can save/spend" : "Projected over by" }
            return insights.surplus >= 0 ? "Saved so far" : "Over by"
        }()

        let commitmentCaption: String? = {
            guard totalCommitment > 0 else { return nil }
            var parts: [String] = []
            if essentialRemaining > 0 {
                parts.append("\(essentialRemaining.currency(currency, approx: essentialProjection?.mixed ?? false)) essentials")
            }
            if piggyAmount > 0 {
                parts.append("\(piggyAmount.currency(currency, approx: piggyCommitment?.mixed ?? false)) piggy")
            }
            if externalAmount > 0 {
                parts.append("\(externalAmount.currency(currency)) savings")
            }
            return parts.joined(separator: " · ") + " still due"
        }()

        return MenuState(lastPaycheck: last, nextPaycheck: next, daysLeft: daysLeft, insights: insights,
                          essentialRemaining: essentialRemaining, piggyAmount: piggyAmount,
                          externalAmount: externalAmount, totalCommitment: totalCommitment,
                          displaySurplus: displaySurplus, displayMixed: displayMixed, currency: currency,
                          savedLabel: savedLabel, commitmentCaption: commitmentCaption)
    }

    var body: some View {
        let state = makeState()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                if let last = state.lastPaycheck {
                    Text("Since \(last.formatted(.dateTime.month(.abbreviated).day()))")
                        .appFont(.headline)
                } else {
                    Text(Date().formatted(.dateTime.month(.wide)))
                        .appFont(.headline)
                }
                Spacer()
                Text(state.lastPaycheck == nil ? "—" : "\(state.daysLeft) days left")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .help(state.nextPaycheck.map { "Next paycheck ~\($0.formatted(.dateTime.month(.abbreviated).day())) (every \(averageInterval) days)" } ?? "")
            }

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text("Income").foregroundStyle(.secondary)
                    Text(state.insights.income.currency(state.currency, approx: state.insights.mixed)).monospacedDigit()
                }
                GridRow {
                    Text("Spent").foregroundStyle(.secondary)
                    Text(state.insights.spent.currency(state.currency, approx: state.insights.mixed)).monospacedDigit()
                }
                Divider()
                GridRow {
                    Text(state.savedLabel)
                        .fontWeight(.semibold)
                    Text(abs(state.displaySurplus).currency(state.currency, approx: state.displayMixed))
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(state.displaySurplus >= 0 ? .green : .red)
                }
            }
            .appFont(.callout)

            if let caption = state.commitmentCaption {
                Text(caption)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await sync.refresh(context: context) }
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 280)
    }
}
