import Foundation

/// Per-piggy pay-period progress tracking, shared by DashboardView (which
/// reads it to compute "still needed this period") and PiggyBanksView (which
/// can write to it via "Mark as paid this period").
///
/// A piggy's own "share due this period" is a day-precise fraction of
/// whatever `leftToSave` happens to be right now (see `Insights.piggyNeed`) —
/// for a long-horizon goal, that fraction barely changes even right after
/// paying it in full, because it's recomputed fresh from a still-large
/// remaining balance. So progress has to be tracked against a FROZEN
/// (target, baseline) pair per piggy, per pay period, rather than re-derived
/// from scratch on every render.
enum PiggyProgress {
    struct Entry {
        var target: Decimal
        var baseline: Decimal
        // True only when the user explicitly clicked "Mark as paid this
        // period" (as opposed to the normal first-seen-this-period freeze) —
        // lets PiggyBanksView show a distinct "already marked" state and
        // offer to undo it, without confusing a manual override for an
        // ordinary frozen entry that simply happens to be settled.
        var manual: Bool
    }

    struct Snapshot {
        let anchor: Double   // the pay period's start, as timeIntervalSinceReferenceDate
        var entries: [String: Entry]   // keyed by piggyID, base currency
    }

    static func parse(_ raw: String) -> Snapshot? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let anchor = Double(parts[0]) else { return nil }
        var entries: [String: Entry] = [:]
        for entry in parts[1].split(separator: ",") {
            let fields = entry.split(separator: ":").map(String.init)
            guard fields.count >= 3, let target = Decimal(string: fields[1]),
                  let baseline = Decimal(string: fields[2]) else { continue }
            let manual = fields.count >= 4 && fields[3] == "1"
            entries[fields[0]] = Entry(target: target, baseline: baseline, manual: manual)
        }
        return Snapshot(anchor: anchor, entries: entries)
    }

    static func format(_ s: Snapshot) -> String {
        let entries = s.entries.keys.sorted()
            .map { "\($0):\(s.entries[$0]!.target):\(s.entries[$0]!.baseline):\(s.entries[$0]!.manual ? "1" : "0")" }
            .joined(separator: ",")
        return "\(s.anchor)|\(entries)"
    }

    /// The current pay period's anchor — the most recent paycheck's
    /// start-of-day — matching what the Dashboard's Payday range freezes
    /// progress against. `nil` when no paycheck has been detected yet.
    static func periodAnchor(in transactions: [FFTransaction]) -> Double? {
        guard let last = transactions.filter(Insights.isPaycheck).map(\.date).max() else { return nil }
        return Calendar.current.startOfDay(for: last).timeIntervalSinceReferenceDate
    }

    /// Whether this piggy currently carries a manual "mark as paid" override
    /// for the CURRENT pay period (a stale override from an earlier, now-
    /// superseded period doesn't count).
    static func isMarkedSettled(rawSnapshot: String, piggyID: String, anchor: Double) -> Bool {
        guard let snapshot = parse(rawSnapshot), snapshot.anchor == anchor else { return false }
        return snapshot.entries[piggyID]?.manual ?? false
    }

    /// Marks a piggy as fully settled for the current pay period: freezes
    /// its target at 0 and its baseline at `currentLeftToSave` (base
    /// currency), so the Dashboard reads €0 still due for it regardless of
    /// what a fresh day-precise recompute would otherwise show. Used when the
    /// user has already paid a piggy's due share directly in Firefly and
    /// wants that reflected immediately, rather than waiting on a recompute
    /// that — for a long-horizon goal — wouldn't actually reach zero on its
    /// own from a single installment.
    static func markSettled(rawSnapshot: String, piggyID: String, currentLeftToSave: Decimal,
                             anchor: Double) -> String {
        var snapshot = parse(rawSnapshot).flatMap { $0.anchor == anchor ? $0 : nil }
            ?? Snapshot(anchor: anchor, entries: [:])
        snapshot.entries[piggyID] = Entry(target: 0, baseline: currentLeftToSave, manual: true)
        return format(snapshot)
    }

    /// Undoes a manual "mark as paid" — simply drops the piggy's frozen
    /// entry so the next render re-freezes it fresh from current numbers, as
    /// if it were newly tracked this period (the same path a brand-new goal
    /// takes). Leaves every other piggy's progress untouched.
    static func clearOverride(rawSnapshot: String, piggyID: String, anchor: Double) -> String {
        guard var snapshot = parse(rawSnapshot), snapshot.anchor == anchor else { return rawSnapshot }
        snapshot.entries.removeValue(forKey: piggyID)
        return format(snapshot)
    }

    /// One line of the piggy-bank breakdown: how much (base currency) still
    /// needs to go into a given account — or, when a piggy isn't linked to
    /// an account, its object group — this period.
    struct BreakdownItem {
        let key: String
        let amount: Decimal
        let mixed: Bool
    }

    struct Commitment {
        let amount: Decimal
        let mixed: Bool
        let breakdown: [BreakdownItem]
    }

    /// This pay period's total piggy-bank commitment, computed from frozen
    /// per-piggy progress — the single implementation shared by the
    /// Dashboard, menu-bar widget, HTML export, and Budgets' essential-piggy-
    /// groups line, so they all always agree. Freezes any newly-tracked
    /// piggy's (target, baseline) fresh and drops any that's no longer
    /// tracked; `window` is the full projected pay period (last paycheck →
    /// estimated next), matching what `Insights.piggyNeed` expects.
    ///
    /// `piggyBanks` may be a FILTERED subset (e.g. just one object group) —
    /// only entries for piggies actually present in it are ever added or
    /// removed, so a caller scoping this to a subset can't silently wipe out
    /// tracking for piggies it doesn't know about (that would otherwise
    /// corrupt the Dashboard's full-portfolio tracking the moment any
    /// narrower caller, like Budgets, rendered first).
    ///
    /// Returns `nil` commitment once nothing's due, alongside the
    /// (possibly-updated) raw snapshot string — callers should persist it
    /// back to their `piggyPeriodSnapshot` storage only when it differs from
    /// what they read, so this stays a rare write, not a per-render one.
    static func commitment(piggyBanks: [FFPiggyBank], window: (start: Date, end: Date),
                            rawSnapshot: String, converter: CurrencyConverter)
        -> (commitment: Commitment?, rawSnapshot: String) {
        let excluded = Insights.piggyPlanExcluded()
        let tracked = piggyBanks.filter { p in
            guard p.targetDate != nil, !excluded.contains(p.piggyID) else { return false }
            if let start = p.startDate, start > Date() { return false }
            return true
        }
        guard !tracked.isEmpty else { return (nil, rawSnapshot) }

        let anchor = window.start.timeIntervalSinceReferenceDate
        let existing = parse(rawSnapshot)
        var entries = existing?.anchor == anchor ? (existing?.entries ?? [:]) : [:]
        var changed = existing?.anchor != anchor

        let trackedIDs = Set(tracked.map(\.piggyID))
        for p in tracked where entries[p.piggyID] == nil {
            let target = converter.convert(Insights.piggyNeed(p, window: window), from: p.currencyCode).amount
            let baseline = converter.convert(p.leftToSave, from: p.currencyCode).amount
            entries[p.piggyID] = Entry(target: target, baseline: baseline, manual: false)
            changed = true
        }
        // Only clean up entries for piggies THIS call actually knows about
        // (every id in the passed-in `piggyBanks`, tracked or not) — an id
        // this call has never heard of (because a caller intentionally
        // passed a narrower subset) is left completely alone.
        let knownIDs = Set(piggyBanks.map(\.piggyID))
        let staleIDs = entries.keys.filter { knownIDs.contains($0) && !trackedIDs.contains($0) }
        if !staleIDs.isEmpty {
            for id in staleIDs { entries.removeValue(forKey: id) }
            changed = true
        }
        let updatedRaw = changed ? format(Snapshot(anchor: anchor, entries: entries)) : rawSnapshot

        var totalStillNeeded: Decimal = 0
        var mixed = false
        var byKey: [String: (amount: Decimal, mixed: Bool)] = [:]
        var keyOrder: [String] = []
        for p in tracked {
            guard let frozen = entries[p.piggyID] else { continue }
            let (currentLeft, converted) = converter.convert(p.leftToSave, from: p.currencyCode)
            let contributed = max(0, frozen.baseline - currentLeft)
            let stillNeeded = max(0, frozen.target - contributed)
            guard stillNeeded > 0 else { continue }
            totalStillNeeded += stillNeeded
            if converted { mixed = true }
            let key = p.accountName ?? p.objectGroup ?? "Ungrouped"
            var entry = byKey[key] ?? (0, false)
            entry.amount += stillNeeded
            entry.mixed = entry.mixed || converted
            byKey[key] = entry
            if !keyOrder.contains(key) { keyOrder.append(key) }
        }
        guard totalStillNeeded > 0 else { return (nil, updatedRaw) }

        let breakdown = keyOrder
            .map { BreakdownItem(key: $0, amount: byKey[$0]!.amount, mixed: byKey[$0]!.mixed) }
            .sorted { $0.amount > $1.amount }
        return (Commitment(amount: totalStillNeeded, mixed: mixed, breakdown: breakdown), updatedRaw)
    }
}
