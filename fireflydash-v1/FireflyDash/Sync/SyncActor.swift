import Foundation
import SwiftData

/// Off-main-thread home for everything CPU-heavy in a sync: parsing hundreds—
/// or, on a first/full sync, tens of thousands—of transactions into `FFTransaction`
/// rows and saving them. `@ModelActor` (SwiftData's background-actor macro)
/// gives this its own `ModelContext` bound to the same store as the app's main
/// context; SwiftUI's `@Query` on the main context picks up the change
/// automatically once `save()` commits, the same way it would for any other
/// context writing to the shared `ModelContainer`.
///
/// Previously this work ran as private methods on the `@MainActor`-isolated
/// `SyncEngine`, with no `await` points in the parsing/upsert loops — so the
/// entire main thread (and the UI) stalled for the duration, on every launch's
/// auto-sync. Moving it here is the fix: the network fetch and JSON decoding
/// already ran off the main thread (via `FireflyAPI`, a plain non-isolated
/// class), but turning the results into model rows didn't.
@ModelActor
actor SyncActor {
    /// Whether this is the very first sync (no prior full sync recorded).
    /// Also creates the `SyncState` row if none exists yet.
    func isFirstRun() throws -> Bool {
        let states = try modelContext.fetch(FetchDescriptor<SyncState>())
        if let s = states.first { return s.lastFullSync == nil }
        let s = SyncState()
        modelContext.insert(s)
        try modelContext.save()
        return true
    }

    /// The persisted last-refresh time, so a fresh `SyncEngine` (created on
    /// each launch) can show it before its own first sync completes.
    func restoreLastRefresh() -> Date? {
        (try? modelContext.fetch(FetchDescriptor<SyncState>()))?.first?.lastRefresh
    }

    /// The newest locally-stored transaction date, for the cheap
    /// "is the server ahead of us?" poll.
    func newestLocalTransactionDate() throws -> Date? {
        var descriptor = FetchDescriptor<FFTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.date
    }

    /// Marks the sync complete and returns the new `lastRefresh` for the
    /// caller's in-memory copy.
    @discardableResult
    func markSynced(isFirstRun: Bool) throws -> Date {
        let states = try modelContext.fetch(FetchDescriptor<SyncState>())
        let state = states.first ?? {
            let s = SyncState()
            modelContext.insert(s)
            return s
        }()
        if isFirstRun { state.lastFullSync = Date() }
        let now = Date()
        state.lastRefresh = now
        try modelContext.save()
        return now
    }

    /// Real data only, per the caller — writes the iPhone HTML snapshot from
    /// this same background context, so it doesn't re-block the main thread
    /// right after a sync (`WebExport` is not `@MainActor`-isolated; only its
    /// `chooseFolder()` NSOpenPanel entry point is).
    func exportWebSnapshotIfNeeded() {
        guard UserDefaults.standard.bool(forKey: WebExport.autoExportKey),
              UserDefaults.standard.data(forKey: WebExport.bookmarkKey) != nil else { return }
        _ = WebExport.export(context: modelContext)
    }

    func upsert(groups: [FFTransactionGroupDTO]) throws {
        // Firefly sends RFC 3339 dates ("2018-09-17T12:46:47+01:00"),
        // occasionally with fractional seconds.
        let iso = Date.ISO8601FormatStyle(timeZoneSeparator: .colon)
        let isoFractional = Date.ISO8601FormatStyle(timeZoneSeparator: .colon,
                                                    includingFractionalSeconds: true)

        let existing = try modelContext.fetch(FetchDescriptor<FFTransaction>())
        var byJournalID = Dictionary(uniqueKeysWithValues: existing.map { ($0.journalID, $0) })

        for group in groups {
            for split in group.attributes.transactions {
                guard let date = (try? iso.parse(split.date))
                    ?? (try? isoFractional.parse(split.date))
                    ?? (try? Date(split.date, strategy: .iso8601)) else { continue }
                let amount = Decimal(string: split.amount) ?? 0
                if let row = byJournalID[split.transaction_journal_id] {
                    row.groupID = group.id
                    row.date = date
                    row.amount = amount
                    row.currencyCode = split.currency_code ?? row.currencyCode
                    row.transactionDescription = split.description
                    row.type = split.type
                    row.categoryName = split.category_name
                    row.budgetName = split.budget_name
                    row.sourceName = split.source_name
                    row.destinationName = split.destination_name
                    row.tags = split.tags ?? []
                    row.notes = split.notes
                    row.foreignAmount = split.foreign_amount.flatMap { Decimal(string: $0) }
                    row.foreignCurrencyCode = split.foreign_currency_code
                } else {
                    let row = FFTransaction(
                        journalID: split.transaction_journal_id,
                        groupID: group.id,
                        date: date,
                        amount: amount,
                        currencyCode: split.currency_code ?? "EUR",
                        transactionDescription: split.description,
                        type: split.type,
                        categoryName: split.category_name,
                        budgetName: split.budget_name,
                        sourceName: split.source_name,
                        destinationName: split.destination_name,
                        tags: split.tags ?? [],
                        notes: split.notes,
                        foreignAmount: split.foreign_amount.flatMap { Decimal(string: $0) },
                        foreignCurrencyCode: split.foreign_currency_code)
                    modelContext.insert(row)
                    byJournalID[split.transaction_journal_id] = row
                }
            }
        }
        try modelContext.save()
    }

    func upsert(piggies: [FFPiggyBankDTO]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<FFPiggyBank>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.piggyID, $0) })
        let incoming = Set(piggies.map(\.id))
        // Piggy banks can be deleted in Firefly; mirror that.
        for row in existing where !incoming.contains(row.piggyID) {
            modelContext.delete(row)
        }
        for dto in piggies {
            let a = dto.attributes
            let current = Decimal(string: a.current_amount ?? "0") ?? 0
            let target = Decimal(string: a.target_amount ?? "0") ?? 0
            let perMonth = Decimal(string: a.save_per_month ?? "0") ?? 0
            let startDate = Self.parseDateOnly(a.start_date)
            let targetDate = Self.parseDateOnly(a.target_date)
            // Account linkage: prefer the legacy single field, else the first of
            // the newer `accounts` array (most piggies attach to one account).
            let accID = a.account_id?.value ?? a.accounts?.first?.account_id?.value
            let accName = a.account_name ?? a.accounts?.first?.name
            if let row = byID[dto.id] {
                row.name = a.name
                row.currentAmount = current
                row.targetAmount = target
                row.currencyCode = a.currency_code ?? row.currencyCode
                row.objectGroup = a.object_group_title
                row.savePerMonth = perMonth
                row.startDate = startDate
                row.targetDate = targetDate
                row.order = a.order ?? 0
                row.groupOrder = a.object_group_order ?? 0
                row.accountID = accID
                row.accountName = accName
            } else {
                modelContext.insert(FFPiggyBank(
                    piggyID: dto.id,
                    name: a.name,
                    currentAmount: current,
                    targetAmount: target,
                    currencyCode: a.currency_code ?? "EUR",
                    objectGroup: a.object_group_title,
                    savePerMonth: perMonth,
                    startDate: startDate,
                    targetDate: targetDate,
                    order: a.order ?? 0,
                    groupOrder: a.object_group_order ?? 0,
                    accountID: accID,
                    accountName: accName))
            }
        }
        try modelContext.save()
    }

    /// Parses a date-only Firefly attribute ("yyyy-MM-dd", occasionally a full
    /// ISO8601 timestamp) into a calendar day.
    private static func parseDateOnly(_ s: String?) -> Date? {
        guard let s else { return nil }
        let parts = s.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return try? Date(s, strategy: .iso8601) }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    func upsert(accounts: [FFAccountDTO]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<FFAccount>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.accountID, $0) })
        for dto in accounts {
            let balance = Decimal(string: dto.attributes.current_balance ?? "0") ?? 0
            if let row = byID[dto.id] {
                row.name = dto.attributes.name
                row.type = dto.attributes.type
                row.currentBalance = balance
                row.currencyCode = dto.attributes.currency_code ?? row.currencyCode
            } else {
                modelContext.insert(FFAccount(
                    accountID: dto.id,
                    name: dto.attributes.name,
                    type: dto.attributes.type,
                    currentBalance: balance,
                    currencyCode: dto.attributes.currency_code ?? "EUR"))
            }
        }
        try modelContext.save()
    }
}
