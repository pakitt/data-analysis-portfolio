import Foundation
import SwiftData

/// Generates ~3 years of realistic, deterministic demo data into a dedicated
/// SwiftData store, so FireflyDash can be showcased (GitHub / LinkedIn) without
/// exposing real finances. The data lands in the same @Model types the Firefly
/// sync writes, so every view reads it through the identical code path — the app
/// can't tell sample data from synced data.
@MainActor
enum SampleData {

    // MARK: Entry points

    /// Populate the container's store if it's empty (first switch / relaunch),
    /// and make sure the demo-only account selections exist either way.
    static func populateIfNeeded(_ container: ModelContainer) {
        let ctx = container.mainContext
        let count = (try? ctx.fetchCount(FetchDescriptor<FFTransaction>())) ?? 0
        if count == 0 { populate(into: ctx) }
        ensureDemoSelections()
    }

    /// Default demo savings/funding selections (stored under the "sample."
    /// namespace, separate from real settings), set only when not already chosen —
    /// so the Dashboard KPIs are populated without clobbering demo tweaks.
    static func ensureDemoSelections() {
        let d = UserDefaults.standard
        if (d.string(forKey: "sample.savingsAccountIDs") ?? "").isEmpty {
            d.set("sample-savings", forKey: "sample.savingsAccountIDs")
        }
        if (d.string(forKey: "sample.fundingAccountIDs") ?? "").isEmpty {
            d.set("sample-checking", forKey: "sample.fundingAccountIDs")
        }
    }

    /// Wipe and rebuild — used by the "Regenerate" button in Settings.
    static func regenerate(into ctx: ModelContext) {
        clear(ctx)
        populate(into: ctx)
    }

    static func clear(_ ctx: ModelContext) {
        for t in (try? ctx.fetch(FetchDescriptor<FFTransaction>())) ?? [] { ctx.delete(t) }
        for a in (try? ctx.fetch(FetchDescriptor<FFAccount>())) ?? [] { ctx.delete(a) }
        for p in (try? ctx.fetch(FetchDescriptor<FFPiggyBank>())) ?? [] { ctx.delete(p) }
        for b in (try? ctx.fetch(FetchDescriptor<FFBudgetLimit>())) ?? [] { ctx.delete(b) }
        try? ctx.save()
    }

    // MARK: Generation

    private static func populate(into ctx: ModelContext) {
        var g = SeededGenerator(seed: 0xF00DCAFE)   // fixed seed → reproducible dataset
        let cal = Calendar.current
        let now = Date()
        let thisMonth = Insights.monthStart(now)
        let firstMonth = cal.date(byAdding: .month, value: -36, to: thisMonth)!

        // Merchant pools for lifelike descriptions.
        let groceries = ["Lidl", "Aldi", "Tesco", "Carrefour", "SuperValu", "Whole Foods Market"]
        let eateries  = ["Trattoria Bella", "Sushi Bar", "The Brunch Spot", "Pizzeria Napoli", "Thai Garden", "Corner Café"]
        let fuel      = ["Shell", "BP", "Esso", "Circle K"]
        let clothing  = ["Zara", "H&M", "Uniqlo", "COS", "Mango"]
        let electronics = ["Apple Store", "MediaMarkt", "Amazon", "Currys"]
        let cinemas   = ["Cineplex", "Theatre Royal", "Picturehouse"]
        let pharmacies = ["City Pharmacy", "Boots", "Apotheke"]
        let doctors   = ["Dr. Nguyen", "Dental Clinic", "Eye Care Center"]
        let grooming  = ["The Barber", "Beauty Lounge", "Hair Studio"]
        let courses   = ["Coursera", "Udemy", "Language School"]
        let airlines  = ["United Airlines", "Delta", "Lufthansa", "Aer Lingus"]
        let hotels    = ["Marriott", "Hilton", "Airbnb", "Ibis Hotel"]
        let checking  = "Everyday Checking"

        var txns: [FFTransaction] = []
        var seq = 0

        func add(_ date: Date, _ amount: Decimal, _ type: String, _ category: String?,
                 _ desc: String, from: String, to: String,
                 budget: String? = nil, tags: [String] = [], usd: Bool = false) {
            guard date <= now, amount > 0 else { return }
            seq += 1
            txns.append(FFTransaction(
                journalID: "s\(seq)", groupID: "sg\(seq)", date: date, amount: amount,
                currencyCode: usd ? "USD" : "EUR",
                transactionDescription: desc, type: type, categoryName: category,
                budgetName: budget, sourceName: from, destinationName: to, tags: tags,
                notes: nil,
                foreignAmount: usd ? cents(amount * eurPerUsd) : nil,
                foreignCurrencyCode: usd ? "EUR" : nil))
        }

        var m = firstMonth
        while m <= thisMonth {
            let monthLen = cal.range(of: .day, in: .month, for: m)!.count
            let mi = cal.component(.month, from: m)   // 1…12, for seasonality
            func day(_ d: Int) -> Date { dateIn(m, min(max(d, 1), monthLen)) }
            func rday() -> Date { day(r(1, monthLen, &g)) }

            // ---- Income ----
            add(day(25), amt(3400, 3750, &g), "deposit", "Salary:Paycheck",
                "Acme Corp — Salary", from: "Acme Corp", to: checking)
            add(day(28), amt(2, 14, &g), "deposit", "Interest",
                "Savings interest", from: "Joint Savings", to: "Joint Savings")
            if mi == 12 {
                add(day(20), amt(1500, 2500, &g), "deposit", "Salary:Bonus",
                    "Year-end bonus", from: "Acme Corp", to: checking)
            }
            if chance(0.15, &g) {
                add(rday(), amt(10, 80, &g), "deposit", "Refund",
                    pick(["Online return refund", "Utility credit", "Friend repayment"], &g),
                    from: "Refund", to: checking)
            }

            // ---- Fixed monthly bills ----
            // Tagged "essential" (the demo mirrors a Firefly rule someone
            // would set up on these categories) so the Dashboard/Budgets
            // essentials projection has something to detect out of the box.
            add(day(1), amt(1550, 1680, &g), "withdrawal", "Home:Rent",
                "Monthly rent", from: checking, to: "Landlord", tags: ["essential"])
            let elec = (mi <= 2 || mi >= 11) ? amt(90, 155, &g) : amt(55, 95, &g)
            add(day(5), elec, "withdrawal", "Utilities:Electricity",
                "PowerCo electricity", from: checking, to: "PowerCo", budget: budgetScope, tags: ["essential"])
            add(day(8), dec("44.99"), "withdrawal", "Utilities:Internet",
                "Fibernet broadband", from: checking, to: "Fibernet", budget: budgetScope, tags: ["essential"])
            add(day(3), dec("12.99"), "withdrawal", "Subscriptions:Streaming",
                "Netflix", from: checking, to: "Netflix", budget: budgetScope)
            add(day(6), dec("10.99"), "withdrawal", "Subscriptions:Music",
                "Spotify", from: checking, to: "Spotify", budget: budgetScope)
            add(day(9), dec("2.99"), "withdrawal", "Subscriptions:Cloud",
                "iCloud+", from: checking, to: "Apple", budget: budgetScope)
            add(day(2), dec("29.99"), "withdrawal", "Healthcare:Gym",
                "FitLife Gym", from: checking, to: "FitLife Gym", budget: budgetScope, tags: ["essential"])
            add(day(12), amt(1, 4, &g), "withdrawal", "Fees & Charges:Bank",
                "Bank service fee", from: checking, to: "Bank Service Fee", tags: ["essential"])

            // ---- Annual car insurance (paid each January, amortised via spread12) ----
            if mi == 1 {
                add(day(15), amt(1050, 1350, &g), "withdrawal", "Auto:Insurance",
                    "Annual car insurance", from: checking, to: "InsureCo", tags: ["spread12", "essential"])
            }

            // ---- Variable spending ----
            for _ in 0..<r(6, 11, &g) {
                let s = pick(groceries, &g)
                add(rday(), amt(14, 95, &g), "withdrawal", "Groceries", s, from: checking, to: s, budget: budgetScope)
            }
            for _ in 0..<r(2, 7, &g) {
                let s = pick(eateries, &g)
                add(rday(), amt(9, 55, &g), "withdrawal", "Eating out", s, from: checking, to: s, budget: budgetScope)
            }
            for _ in 0..<r(1, 3, &g) {
                let s = pick(fuel, &g)
                add(rday(), amt(45, 85, &g), "withdrawal", "Auto:Fuel", s, from: checking, to: s, budget: budgetScope)
            }
            for _ in 0..<r(0, 4, &g) {
                add(rday(), amt(2, 4, &g), "withdrawal", "Public transport:Ticket",
                    "Transit ticket", from: "Cash", to: "City Transit", budget: budgetScope)
            }
            for _ in 0..<r(0, 3, &g) {
                let s = pick(clothing, &g)
                add(rday(), amt(18, 140, &g), "withdrawal", "Shopping:Clothing", s, from: checking, to: s, budget: budgetScope)
            }
            if chance(0.25, &g) {
                let s = pick(electronics, &g)
                add(rday(), amt(30, 450, &g), "withdrawal", "Shopping:Electronics", s, from: checking, to: s, budget: budgetScope)
            }
            for _ in 0..<r(0, 3, &g) {
                let s = pick(cinemas, &g)
                add(rday(), amt(9, 32, &g), "withdrawal", "Entertainment:Cinema", s, from: checking, to: s, budget: budgetScope)
            }
            if chance(0.10, &g) {
                add(rday(), amt(40, 120, &g), "withdrawal", "Entertainment:Concert",
                    "Live concert", from: checking, to: "Concert Hall", budget: budgetScope)
            }
            for _ in 0..<r(0, 3, &g) {
                let s = pick(pharmacies, &g)
                add(rday(), amt(4, 45, &g), "withdrawal", "Healthcare:Pharmacy", s, from: checking, to: s, budget: budgetScope)
            }
            if chance(0.20, &g) {
                let s = pick(doctors, &g)
                add(rday(), amt(20, 130, &g), "withdrawal", "Healthcare:Doctor", s, from: checking, to: s)
            }
            for _ in 0..<r(0, 2, &g) {
                let s = pick(grooming, &g)
                add(rday(), amt(12, 65, &g), "withdrawal", "Personal Care", s, from: checking, to: s, budget: budgetScope)
            }
            if chance(0.15, &g) {
                let s = pick(courses, &g)
                add(rday(), amt(40, 260, &g), "withdrawal", "Education:Course", s, from: checking, to: s)
            }

            // ---- Trips (summer in USD, others in EUR) ----
            let isSummer = (mi == 7 || mi == 8)
            let tripChance = isSummer ? 0.7 : ([4, 12].contains(mi) ? 0.4 : 0.0)
            if chance(tripChance, &g) {
                let usd = isSummer
                // Tag every leg of a trip so it reads as one cross-category
                // "project" in the tag tracker (a summer/spring trip per year).
                let tripTag = "\(isSummer ? "Summer" : "Spring") trip \(cal.component(.year, from: m))"
                add(day(r(2, 10, &g)), amt(180, 620, &g), "withdrawal", "Travel:Flights",
                    pick(airlines, &g), from: checking, to: "Airline", tags: [tripTag], usd: usd)
                for _ in 0..<r(1, 3, &g) {
                    add(day(r(10, 24, &g)), amt(90, 280, &g), "withdrawal", "Travel:Hotels",
                        pick(hotels, &g), from: checking, to: "Hotel", tags: [tripTag], usd: usd)
                }
                for _ in 0..<r(1, 2, &g) {
                    add(day(r(10, 24, &g)), amt(20, 75, &g), "withdrawal", "Eating out",
                        "Dinner abroad", from: checking, to: "Restaurant", tags: [tripTag], usd: usd)
                }
            }

            // ---- Monthly top-up of savings (a transfer; not income/expense) ----
            add(day(26), amt(300, 600, &g), "transfer", nil,
                "Transfer to savings", from: checking, to: "Joint Savings")

            m = cal.date(byAdding: .month, value: 1, to: m)!
        }

        txns.forEach(ctx.insert)
        accounts().forEach(ctx.insert)
        piggies().forEach(ctx.insert)
        try? ctx.save()
    }

    // MARK: Accounts & piggy banks

    private static func accounts() -> [FFAccount] {
        [
            FFAccount(accountID: "sample-checking", name: "Everyday Checking", type: "asset",
                      currentBalance: dec("4280.55"), currencyCode: "EUR"),
            FFAccount(accountID: "sample-savings", name: "Joint Savings", type: "asset",
                      currentBalance: dec("18500.00"), currencyCode: "EUR"),
            FFAccount(accountID: "sample-cash", name: "Cash Wallet", type: "asset",
                      currentBalance: dec("240.00"), currencyCode: "EUR"),
        ]
    }

    private static func piggies() -> [FFPiggyBank] {
        let cal = Calendar.current
        let carTarget = cal.date(byAdding: .month, value: 24, to: Date())
        let holiday = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))
        func p(_ id: String, _ name: String, _ current: String, _ target: String,
               group: String?, groupOrder: Int, order: Int,
               perMonth: String = "0", date: Date? = nil) -> FFPiggyBank {
            FFPiggyBank(piggyID: id, name: name, currentAmount: dec(current),
                        targetAmount: dec(target), currencyCode: "EUR",
                        objectGroup: group, savePerMonth: dec(perMonth), targetDate: date,
                        order: order, groupOrder: groupOrder,
                        accountID: "sample-savings", accountName: "Joint Savings")
        }
        return [
            p("sample-piggy-laptop", "New Laptop", "2000", "2000",
              group: nil, groupOrder: 0, order: 1),
            p("sample-piggy-rainy", "Rainy Day Fund", "7500", "10000",
              group: "Safety net", groupOrder: 1, order: 1, perMonth: "250"),
            p("sample-piggy-car", "New Car", "4200", "15000",
              group: "Goals", groupOrder: 2, order: 1, perMonth: "350", date: carTarget),
            p("sample-piggy-holiday", "Summer Holiday", "2100", "3000",
              group: "Goals", groupOrder: 2, order: 2, perMonth: "300", date: holiday),
        ]
    }

    // MARK: Helpers

    /// Most expenses count toward this scope so the Budgets view has data
    /// (it matches budgetName/tag against the user's "Monthly budget" scope).
    private static let budgetScope = "Monthly budget"
    /// Inferred FX so USD trips convert cleanly (and surface the ≈ marker).
    private static let eurPerUsd = dec("0.92")

    private static func dateIn(_ monthAnchor: Date, _ d: Int) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month], from: monthAnchor)
        var dc = DateComponents()
        dc.year = c.year; dc.month = c.month; dc.day = d; dc.hour = 12
        return cal.date(from: dc) ?? monthAnchor
    }
}

// MARK: - Small value helpers

private func dec(_ s: String) -> Decimal { Decimal(string: s) ?? 0 }

private func cents(_ d: Decimal) -> Decimal {
    var v = d, r = Decimal()
    NSDecimalRound(&r, &v, 2, .plain)
    return r
}

private func amt(_ lo: Double, _ hi: Double, _ g: inout SeededGenerator) -> Decimal {
    let c = Int.random(in: Int(lo * 100)...Int(hi * 100), using: &g)
    return Decimal(c) / 100
}

private func r(_ lo: Int, _ hi: Int, _ g: inout SeededGenerator) -> Int {
    Int.random(in: lo...max(lo, hi), using: &g)
}

private func pick<T>(_ arr: [T], _ g: inout SeededGenerator) -> T {
    arr[Int.random(in: 0..<arr.count, using: &g)]
}

private func chance(_ p: Double, _ g: inout SeededGenerator) -> Bool {
    p > 0 && Double.random(in: 0..<1, using: &g) < p
}

/// Deterministic SplitMix64 PRNG, so the demo dataset is identical every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
