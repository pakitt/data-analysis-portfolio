import Foundation

/// Pure aggregation helpers — all charts are computed from the local SwiftData copy.
struct MonthInsights {
    let month: Date            // first day of month
    let income: Decimal
    let spent: Decimal
    let byCategory: [(category: String, amount: Decimal)]   // expenses, descending; base currency
    /// True when income or spending combined more than one currency.
    var mixed: Bool = false
    /// Categories whose total includes amounts converted from another currency.
    var byCategoryMixed: Set<String> = []

    var surplus: Decimal { income - spent }
}

/// Converts amounts into the user's base currency.
///
/// Rates come from the data itself: whenever a transaction touches two
/// currencies (e.g. a transfer between a € and a $ account) Firefly records
/// the converted amount, which fixes the exchange rate on that date. Every
/// such pairing is kept as a dated observation, so conversions use the rate
/// closest in time to the amount being converted — an old transaction is
/// valued at an old rate, a current balance at the most recent one. Amounts
/// with no recorded conversion of their own fall back to this historical
/// series. Currencies never seen in a pair with the base are kept at face
/// value — every converted or face-value amount is flagged so totals that
/// combine currencies can be marked (≈).
struct CurrencyConverter {
    let base: String
    /// Per currency, the observed (date, rate) pairs sorted oldest first.
    /// Rate is base units per 1 unit of the other currency.
    private var observations: [String: [(date: Date, rate: Decimal)]] = [:]

    init(base: String, transactions: [FFTransaction]) {
        self.base = base
        var obs: [String: [(date: Date, rate: Decimal)]] = [:]
        for t in transactions {
            guard let fa = t.foreignAmount, let fc = t.foreignCurrencyCode,
                  fa != 0, t.amount != 0 else { continue }
            if fc == base, t.currencyCode != base {
                obs[t.currencyCode, default: []].append((t.date, fa / t.amount))
            } else if t.currencyCode == base, fc != base {
                obs[fc, default: []].append((t.date, t.amount / fa))
            }
        }
        for (code, series) in obs {
            observations[code] = series.sorted { $0.date < $1.date }
        }
    }

    /// The rate for `code` effective at `date`: the observation nearest in
    /// time. nil when the currency was never paired with the base.
    private func rate(for code: String, on date: Date) -> Decimal? {
        guard let series = observations[code], !series.isEmpty else { return nil }
        return series.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }!.rate
    }

    /// A bare amount in a given currency → base currency, using the rate
    /// nearest `date`. The default (`.distantFuture`) selects the newest rate,
    /// which is what a current balance wants.
    func convert(_ amount: Decimal, from code: String,
                 on date: Date = .distantFuture) -> (amount: Decimal, converted: Bool) {
        if code == base { return (amount, false) }
        if let rate = rate(for: code, on: date) { return (amount * rate, true) }
        return (amount, true)   // no rate known: face value, still flagged
    }

    /// A transaction's amount in the base currency. The transaction's own
    /// recorded conversion (exact, dated) beats the inferred rate; otherwise the
    /// historical rate nearest the transaction's date is used.
    func value(_ t: FFTransaction) -> (amount: Decimal, converted: Bool) {
        if t.currencyCode == base { return (t.amount, false) }
        if t.foreignCurrencyCode == base, let fa = t.foreignAmount { return (fa, true) }
        return convert(t.amount, from: t.currencyCode, on: t.date)
    }
}

enum Insights {
    /// Categories the user has chosen to hide from every view (Settings).
    /// Stored newline-separated because category names may contain commas.
    static func excludedCategories() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: AppSettings.key("excludedCategories")) ?? ""
        return Set(raw.split(separator: "\n").map(String.init))
    }

    /// Case-insensitive tag that marks a transaction as essential spending
    /// (Settings) — configurable, same pattern as the paycheck keyword. Set
    /// up a Firefly rule to apply it on import (e.g. to rent, insurance,
    /// subscriptions); untagged transactions are discretionary.
    static func essentialTag() -> String {
        let raw = (UserDefaults.standard.string(forKey: AppSettings.key("essentialTag")) ?? "")
            .trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "essential" : raw
    }

    static func isEssential(_ t: FFTransaction) -> Bool {
        let tag = essentialTag()
        return t.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
    }

    // MARK: Piggy banks

    /// Piggy banks the user has excluded from the monthly savings plan
    /// (Piggy Banks view) — e.g. a soft goal with a date they don't want
    /// forced every period. Stored as piggy IDs, newline-separated.
    static func piggyPlanExcluded() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: AppSettings.key("piggyPlanExcluded")) ?? ""
        return Set(raw.split(separator: "\n").map(String.init))
    }

    /// Whether this piggy currently needs any contribution at all: it isn't
    /// already funded, has a target date to aim for (a placeholder goal with
    /// no date needs nothing), and — if it has a start date — has actually
    /// started.
    static func piggyIsActive(_ p: FFPiggyBank, on date: Date = Date()) -> Bool {
        guard p.leftToSave > 0, p.targetDate != nil else { return false }
        if let start = p.startDate, start > date { return false }
        return true
    }

    /// How much should go into this piggy within `window` (an in-progress pay
    /// period, say) — 0 when `piggyIsActive` is false. Deliberately does NOT
    /// use Firefly's own `savePerMonth` (it can be wrong — observed case: a
    /// 3-month goal reported a per-month figure too low to ever reach the
    /// target in time). If the target date falls inside (or before) the
    /// window, the WHOLE remainder is due within it — capped there, never
    /// more — otherwise this is the remainder's share of the window's length
    /// relative to the total time actually left until the target. (Naively
    /// turning a short deadline into "an implied monthly rate" and then
    /// re-scaling that rate to the window double-counts short-fuse goals —
    /// an €1,050 goal due in 8 days needs €1,050 this pay period, not a
    /// ~€3,990 "monthly pace" mostly surviving a second, roughly-1× scaling.)
    /// Native currency; the caller converts to base.
    static func piggyNeed(_ p: FFPiggyBank, window: (start: Date, end: Date), asOf: Date = Date()) -> Decimal {
        guard piggyIsActive(p, on: asOf), let target = p.targetDate else { return 0 }
        let daysToTarget = Calendar.current.dateComponents([.day], from: asOf, to: target).day ?? 0
        guard daysToTarget > 0 else { return p.leftToSave }
        let windowDays = Calendar.current.dateComponents([.day], from: window.start, to: window.end).day ?? 0
        let share = min(Double(windowDays), Double(daysToTarget)) / Double(daysToTarget)
        return p.leftToSave * Decimal(share)
    }


    // MARK: Paychecks

    /// When paychecks became regular: income before this date is ignored when
    /// estimating the pay cadence. Defaults to 1 Feb 2026; set in Settings.
    static let defaultPaycheckStart = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!

    /// Case-insensitive keyword that marks an income transaction as a regular
    /// paycheck, matched against its category name. Configurable in Settings.
    static func paycheckKeyword() -> String {
        let raw = (UserDefaults.standard.string(forKey: AppSettings.key("paycheckKeyword")) ?? "")
            .trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "paycheck" : raw
    }

    /// The configured regular-cadence start date (see `defaultPaycheckStart`).
    static func paycheckStart() -> Date {
        let ts = UserDefaults.standard.double(forKey: AppSettings.key("paycheckStartTS"))
        return ts == 0 ? defaultPaycheckStart : Date(timeIntervalSinceReferenceDate: ts)
    }

    /// Whether a transaction is a regular paycheck: income, on/after the
    /// configured start date, whose category contains the configured keyword.
    static func isPaycheck(_ t: FFTransaction) -> Bool {
        t.isIncome
            && (t.categoryName?.localizedCaseInsensitiveContains(paycheckKeyword()) ?? false)
            && t.date >= paycheckStart()
    }

    /// Mean gap between consecutive paychecks (days); 30 until two are on record.
    static func averagePaycheckInterval(_ transactions: [FFTransaction]) -> Int {
        let dates = transactions.filter(isPaycheck).map(\.date).sorted()
        guard dates.count >= 2 else { return 30 }
        let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / 86_400 }
        return max(Int((gaps.reduce(0, +) / Double(gaps.count)).rounded()), 1)
    }

    /// Estimated next paycheck date: `last` + the historical average cadence.
    static func nextPaycheckEstimate(after last: Date, in transactions: [FFTransaction]) -> Date {
        Calendar.current.date(byAdding: .day, value: averagePaycheckInterval(transactions), to: last)!
    }

    /// Apply the global category exclusion. Every view should pass its
    /// transactions through this before computing anything.
    static func visible(_ transactions: [FFTransaction]) -> [FFTransaction] {
        let excluded = excludedCategories()
        guard !excluded.isEmpty else { return transactions }
        return transactions.filter { !excluded.contains($0.categoryName ?? "Uncategorised") }
    }

    // MARK: Amortisation ("spreadN" tags)

    /// A transaction tagged `spreadN` (N ≥ 2) is a lump sum covering N months
    /// (annual insurance → spread12, a bi-monthly bill → spread2). Returns N,
    /// or nil when no such tag is present.
    static func spreadMonths(_ t: FFTransaction) -> Int? {
        for tag in t.tags {
            let lower = tag.lowercased()
            guard lower.hasPrefix("spread"), let n = Int(lower.dropFirst(6)), n >= 2 else { continue }
            return n
        }
        return nil
    }

    /// The transactions every *aggregation* should run on: category-excluded,
    /// and — when the amortised view is on — with each `spreadN`-tagged expense
    /// replaced by N equal slivers, one per month from the month it was paid.
    /// Income is never spread. The slivers are transient (never saved); use this
    /// only for summing, not for listing rows.
    static func entries(_ transactions: [FFTransaction], amortize: Bool) -> [FFTransaction] {
        let base = visible(transactions)
        guard amortize else { return base }
        let cal = Calendar.current
        var out: [FFTransaction] = []
        out.reserveCapacity(base.count)
        for t in base {
            guard t.isExpense, let n = spreadMonths(t) else { out.append(t); continue }
            let share = t.amount / Decimal(n)
            let foreignShare = t.foreignAmount.map { $0 / Decimal(n) }
            for k in 0..<n {
                let date = cal.date(byAdding: .month, value: k, to: t.date) ?? t.date
                out.append(FFTransaction(
                    journalID: "\(t.journalID)#a\(k)", groupID: t.groupID, date: date,
                    amount: share, currencyCode: t.currencyCode,
                    transactionDescription: t.transactionDescription, type: t.type,
                    categoryName: t.categoryName, budgetName: t.budgetName,
                    sourceName: t.sourceName, destinationName: t.destinationName,
                    tags: t.tags, notes: t.notes,
                    foreignAmount: foreignShare, foreignCurrencyCode: t.foreignCurrencyCode))
            }
        }
        return out
    }

    /// Paolo's convention: "Main:Subcategory". Returns the parts, trimmed.
    static func splitCategory(_ name: String) -> (main: String, sub: String?) {
        guard let idx = name.firstIndex(of: ":") else { return (name.trimmingCharacters(in: .whitespaces), nil) }
        let main = String(name[..<idx]).trimmingCharacters(in: .whitespaces)
        let sub = String(name[name.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        return (main, sub.isEmpty ? nil : sub)
    }

    static func monthStart(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date))!
    }

    /// The currency every total is reported in: the user's explicit choice
    /// (Settings → Currency) or, by default, the most-used transaction currency.
    static func baseCurrency(_ transactions: [FFTransaction]) -> String {
        if let chosen = UserDefaults.standard.string(forKey: AppSettings.key("baseCurrency")), !chosen.isEmpty {
            return chosen
        }
        var counts: [String: Int] = [:]
        for t in transactions { counts[t.currencyCode, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? "EUR"
    }

    static func converter(for transactions: [FFTransaction]) -> CurrencyConverter {
        CurrencyConverter(base: baseCurrency(transactions), transactions: transactions)
    }

    static func insights(for month: Date, in transactions: [FFTransaction],
                         converter: CurrencyConverter? = nil) -> MonthInsights {
        let start = monthStart(month)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        return range(start: start, end: end, in: transactions, converter: converter)
    }

    /// Aggregates over an arbitrary date range, in the base currency.
    static func range(start: Date, end: Date, in transactions: [FFTransaction],
                      converter: CurrencyConverter? = nil) -> MonthInsights {
        let conv = converter ?? Self.converter(for: transactions)
        let slice = transactions.filter { $0.date >= start && $0.date < end }

        var income: Decimal = 0
        var spent: Decimal = 0
        var mixed = false
        var cat: [String: Decimal] = [:]
        var catMixed: Set<String> = []

        for t in slice {
            if t.isIncome {
                let (v, converted) = conv.value(t)
                income += v
                if converted { mixed = true }
            } else if t.isExpense {
                let (v, converted) = conv.value(t)
                spent += v
                let label = t.categoryLabel
                cat[label, default: 0] += v
                if converted { mixed = true; catMixed.insert(label) }
            }
        }
        let byCategory = cat.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }

        return MonthInsights(month: start, income: income, spent: spent,
                             byCategory: byCategory, mixed: mixed, byCategoryMixed: catMixed)
    }

    /// Last `count` months of (month, income, spent), oldest first.
    static func monthlySeries(count: Int, in transactions: [FFTransaction]) -> [MonthInsights] {
        let conv = converter(for: transactions)
        let thisMonth = monthStart(Date())
        return (0..<count).reversed().compactMap { offset in
            guard let m = Calendar.current.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return insights(for: m, in: transactions, converter: conv)
        }
    }

    /// Group full "Main:Sub" category totals by main category, keeping the
    /// per-subcategory breakdown (descending) for hover details. A main is
    /// `mixed` when any member category combined currencies.
    static func mainBreakdown(_ byCategory: [(category: String, amount: Decimal)],
                              mixedCategories: Set<String> = [])
        -> [(main: String, amount: Decimal, subs: [(label: String, amount: Decimal)], mixed: Bool)] {
        var mains: [String: (total: Decimal, subs: [String: Decimal], mixed: Bool)] = [:]
        for c in byCategory {
            let (main, sub) = splitCategory(c.category)
            var entry = mains[main] ?? (0, [:], false)
            entry.total += c.amount
            if let sub { entry.subs[sub, default: 0] += c.amount }
            if mixedCategories.contains(c.category) { entry.mixed = true }
            mains[main] = entry
        }
        return mains
            .map { (main: $0.key, amount: $0.value.total,
                    subs: $0.value.subs.sorted { $0.value > $1.value }
                        .map { (label: $0.key, amount: $0.value) },
                    mixed: $0.value.mixed) }
            .sorted { $0.amount > $1.amount }
    }

    /// One entry in a category breakdown (a main category and its subs).
    typealias MainEntry = (main: String, amount: Decimal, subs: [(label: String, amount: Decimal)], mixed: Bool)

    /// Roll main categories below `thresholdPercent` of the total into a single
    /// trailing "Other" bucket — so the donut/pie charts honour the same
    /// Subcategory-threshold setting as the Cashflow chart. The collapsed mains
    /// become "Other"'s breakdown, so its hover detail still itemises them.
    static func collapseSmall(_ mains: [MainEntry], thresholdPercent: Double) -> [MainEntry] {
        guard thresholdPercent > 0 else { return mains }
        let total = mains.reduce(Decimal(0)) { $0 + $1.amount }
        let threshold = total * Decimal(thresholdPercent / 100)
        let small = mains.filter { $0.amount < threshold }
        guard small.count > 1 else { return mains }   // nothing gained collapsing a lone slice

        var big = mains.filter { $0.amount >= threshold }
        let otherSubs = small.map { (label: $0.main, amount: $0.amount) }
            .sorted { $0.amount > $1.amount }
        big.append((main: "Other",
                    amount: small.reduce(Decimal(0)) { $0 + $1.amount },
                    subs: otherSubs,
                    mixed: small.contains { $0.mixed }))
        return big
    }

    static func average(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Decimal(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func median(_ values: [Decimal]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    // MARK: Essential-spend projection ("what's still coming")

    /// A detected recurring essential bill: a category (optionally split by
    /// biller) that historically arrives on a roughly fixed cadence.
    struct BillProjection: Identifiable {
        var id: String { "\(category)|\(biller ?? "")" }
        let category: String
        /// The counterparty (Firefly's destination account), when distinct
        /// from the category itself — lets several billers share one category.
        let biller: String?
        let typicalAmount: Decimal
        let cadenceDays: Int
        let lastPaidDate: Date
        let expectedDate: Date
        /// True when this biller already recurred within the current window —
        /// it's settled, not counted in `expectedRemaining`.
        let alreadyPaidThisPeriod: Bool
    }

    /// A frequent, variable essential category (groceries, fuel — too many
    /// different billers to predict a cadence from) projected via its
    /// historical monthly average rather than a per-biller schedule.
    struct VariableEssential: Identifiable {
        var id: String { category }
        let category: String
        /// Historical-average total expected for the whole window.
        let expectedTotal: Decimal
        /// Actually spent in this category within the window so far.
        let spentSoFar: Decimal
        var remaining: Decimal { max(0, expectedTotal - spentSoFar) }
    }

    struct EssentialProjection {
        /// Essential-only, actual, in [window.start, asOf).
        let spentSoFar: Decimal
        /// Essential-only, projected, in [asOf, window.end).
        let expectedRemaining: Decimal
        let mixed: Bool
        /// Recurring bills behind `expectedRemaining`, for a transparency list.
        let bills: [BillProjection]
        /// Variable essential categories behind `expectedRemaining` too — the
        /// other half of the transparency list `bills` alone didn't cover.
        let variableCategories: [VariableEssential]
        /// Discretionary (untagged) spend, actual, in [window.start, asOf) —
        /// context alongside the essential figures above; never projected
        /// forward and never counted in `expectedRemaining`/any total here.
        let discretionarySpentSoFar: Decimal
        let discretionaryMixed: Bool
    }

    /// How many of a recurring bill's most recent occurrences its typical
    /// amount/cadence are derived from (see `essentialProjection`) — capped
    /// by COUNT rather than by a fixed time window, so a genuine repricing
    /// only needs to outnumber a handful of recent payments to be reflected,
    /// not an entire lookback's worth of the old amount.
    static let recentOccurrences = 6

    /// Projects how much more ESSENTIAL spending (Settings → essential tag —
    /// transactions carrying it, typically set by a Firefly rule on import)
    /// is likely before `window.end`. Categories that
    /// recur as a single roughly-monthly lump (rent, insurance, subscriptions)
    /// are predicted per biller from their own historical cadence; frequent,
    /// variable essential categories (groceries, fuel) fall back to a
    /// historical monthly average scaled to the window length.
    ///
    /// Detection always runs on REAL transaction dates (`visible`), independent
    /// of the amortise toggle — bill timing and lump-sum smoothing answer
    /// different questions, and mixing them risks double counting.
    ///
    /// `asOf` is the actual/projected cutoff (normally `min(Date(), window.end)`):
    /// spend before it is actual, spend after it is projected. When `asOf >=
    /// window.end` (a fully past period) this always returns zero projected
    /// remaining — the whole window is already actual.
    static func essentialProjection(window: (start: Date, end: Date), asOf: Date,
                                    in allTransactions: [FFTransaction]) -> EssentialProjection {
        let cal = Calendar.current
        let real = visible(allTransactions)
        let conv = converter(for: real)

        var spentSoFar: Decimal = 0
        var mixed = false
        var discretionarySpentSoFar: Decimal = 0
        var discretionaryMixed = false
        for t in real where t.isExpense && t.date >= window.start && t.date < asOf {
            let (v, converted) = conv.value(t)
            if isEssential(t) {
                spentSoFar += v
                if converted { mixed = true }
            } else {
                discretionarySpentSoFar += v
                if converted { discretionaryMixed = true }
            }
        }

        guard asOf < window.end else {
            return EssentialProjection(spentSoFar: spentSoFar, expectedRemaining: 0, mixed: mixed, bills: [],
                                       variableCategories: [], discretionarySpentSoFar: discretionarySpentSoFar,
                                       discretionaryMixed: discretionaryMixed)
        }

        let lookbackStart = cal.date(byAdding: .day, value: -400, to: asOf)!
        // `spread12`-tagged transactions specifically (an annual insurance
        // premium, etc.) are excluded from bill/variable detection: they're
        // big, once-a-year lumps that would otherwise get (mis)detected as
        // "a recurring bill due on this date" — the actual plan for them is
        // a piggy bank funded gradually (see the Budgets essential-piggy-
        // groups line), not a predicted transaction. Shorter spreads
        // (spread2, spread3 — a bimonthly/quarterly bill just amortised for
        // trend-smoothing elsewhere) are still genuine recurring bills here
        // and stay in detection.
        let history = real.filter {
            $0.isExpense && $0.date >= lookbackStart && $0.date <= asOf && isEssential($0)
                && spreadMonths($0) != 12
        }
        let lookbackMonths = max(Double(cal.dateComponents([.day], from: lookbackStart, to: asOf).day ?? 400) / 30.4, 1)
        let windowDays = Double(cal.dateComponents([.day], from: window.start, to: window.end).day ?? 30)
        // Last 3 COMPLETE past months (like Averages/Budgets), for the variable-category fallback.
        let completeMonths = Array(monthlySeries(count: 4, in: real).dropLast())

        var expectedRemaining: Decimal = 0
        var bills: [BillProjection] = []
        var variableCategories: [VariableEssential] = []

        for (category, txns) in Dictionary(grouping: history, by: \.categoryLabel) {
            let avgPerMonth = Double(txns.count) / lookbackMonths
            let spentInCategoryThisWindow = txns.filter { $0.date >= window.start && $0.date < asOf }
                .reduce(Decimal(0)) { $0 + conv.value($1).amount }

            // A category only behaves like "a recurring bill" if it's actually
            // dominated by one biller (rent → the landlord, insurance → the
            // insurer). A category spread across many different counterparties
            // (e.g. fuel bought at whichever petrol station is nearby) isn't a
            // fixed bill even if the overall frequency is low — each biller's
            // own history is too sparse to predict a reliable cadence from, so
            // splitting it per biller produces noisy, often stale "still due"
            // guesses. Such categories fall through to the variable/average
            // method below instead, which naturally aggregates every biller.
            let billerCounts = Dictionary(grouping: txns, by: { $0.destinationName ?? category })
                .mapValues(\.count)
            let dominantBillerShare = Double(billerCounts.values.max() ?? 0) / Double(max(txns.count, 1))

            if avgPerMonth < 2 && dominantBillerShare >= 0.5 {
                // Recurring-bill category: detect per biller (destination account).
                for (biller, fullSeries) in Dictionary(grouping: txns, by: { $0.destinationName ?? category }) {
                    guard fullSeries.count >= 3 else { continue }
                    // Cadence and typical amount are derived from only the
                    // LAST `recentOccurrences` payments, not the whole
                    // 400-day lookback — a median over everything is slow to
                    // reflect a genuine repricing (a new contract/tariff):
                    // it has to wait until the new amount outnumbers a
                    // year's worth of the old one. Capping by occurrence
                    // count instead means a real change only needs to
                    // outnumber a handful of recent payments, while still
                    // keeping the noise-smoothing a median gives over a
                    // single (possibly one-off/erroneous) payment.
                    let series = Array(fullSeries.sorted { $0.date < $1.date }.suffix(Self.recentOccurrences))
                    let dates = series.map(\.date)
                    let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / 86_400 }
                    let cadenceDays = Int(median(gaps).rounded())
                    guard cadenceDays >= 7 else { continue }
                    let typicalAmount = median(series.map { conv.value($0).amount })
                    let expectedDate = cal.date(byAdding: .day, value: cadenceDays, to: dates.last!)!
                    // A few days' grace BEFORE the window start: bills often
                    // process a day or two early around a weekend or month-end
                    // (e.g. an insurance premium landing Jun 30 for Jul's cover)
                    // — without this, that payment falls just outside the
                    // window and the bill wrongly reads "still due" for a
                    // period it already covered.
                    //
                    // Matched against the whole CATEGORY (not just this
                    // biller's own destination name) within an amount
                    // tolerance: banks occasionally resolve a merchant name
                    // for the first time (e.g. a generic "Healthcare"
                    // placeholder finally becoming "VHI"), which would
                    // otherwise look like a brand-new, too-sparse biller and
                    // leave the original series wrongly reading "still due"
                    // forever even though it was, in fact, paid.
                    let paidGraceStart = cal.date(byAdding: .day, value: -5, to: window.start)!
                    let paidMatch = txns.filter {
                        $0.date >= paidGraceStart && $0.date < asOf
                            && abs(conv.value($0).amount - typicalAmount) <= typicalAmount * 0.3
                    }.max { $0.date < $1.date }
                    let alreadyPaid = paidMatch != nil
                    let lastPaidDate = paidMatch?.date ?? dates.last!
                    // Reject stale predictions: a biller that hasn't recurred
                    // in well over a cycle (e.g. a one-off pair of fill-ups at
                    // the same petrol station) shouldn't be projected forever
                    // just because its old `expectedDate` sits in the past.
                    let earliestRelevant = cal.date(byAdding: .day, value: -cadenceDays, to: window.start)!
                    guard expectedDate >= earliestRelevant else { continue }
                    // Keep it in the list (paid, for the transparency check) as
                    // long as it's relevant to this window; only add unpaid
                    // ones to the running total.
                    guard alreadyPaid || expectedDate <= window.end else { continue }
                    if !alreadyPaid {
                        expectedRemaining += typicalAmount
                        if series.contains(where: { conv.value($0).converted }) { mixed = true }
                    }
                    bills.append(BillProjection(category: category, biller: biller == category ? nil : biller,
                                                typicalAmount: typicalAmount, cadenceDays: cadenceDays,
                                                lastPaidDate: lastPaidDate, expectedDate: expectedDate,
                                                alreadyPaidThisPeriod: alreadyPaid))
                }
            } else {
                // Variable category: historical monthly average scaled to the
                // window length, minus what's already been spent within it.
                let monthlyAvg = average(completeMonths.map { m in
                    m.byCategory.first { $0.category == category }?.amount ?? 0
                })
                let expectedTotalForWindow = monthlyAvg * Decimal(windowDays / 30.4)
                expectedRemaining += max(0, expectedTotalForWindow - spentInCategoryThisWindow)
                if expectedTotalForWindow > 0 {
                    variableCategories.append(VariableEssential(category: category, expectedTotal: expectedTotalForWindow,
                                                                 spentSoFar: spentInCategoryThisWindow))
                }
            }
        }

        return EssentialProjection(spentSoFar: spentSoFar, expectedRemaining: expectedRemaining,
                                   mixed: mixed, bills: bills.sorted { $0.expectedDate < $1.expectedDate },
                                   variableCategories: variableCategories.sorted { $0.expectedTotal > $1.expectedTotal },
                                   discretionarySpentSoFar: discretionarySpentSoFar,
                                   discretionaryMixed: discretionaryMixed)
    }
}

extension Decimal {
    var doubleValue: Double { Double(description) ?? 0 }

    func currency(_ code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// "≈" marks an amount that combines more than one currency.
    func currency(_ code: String, approx: Bool) -> String {
        (approx ? "≈" : "") + currency(code)
    }
}
