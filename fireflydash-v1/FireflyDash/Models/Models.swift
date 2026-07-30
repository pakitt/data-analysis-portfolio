import Foundation
import SwiftData

/// A single transaction split, flattened from Firefly III's journal/group model.
/// Firefly groups splits under a transaction group; for a viewer we flatten each
/// split into its own row and keep the group id for traceability.
@Model
final class FFTransaction {
    /// Firefly journal id — unique per split, used as the upsert key.
    @Attribute(.unique) var journalID: String
    var groupID: String
    var date: Date
    var amount: Decimal
    var currencyCode: String
    var transactionDescription: String
    /// "withdrawal", "deposit", "transfer"
    var type: String
    var categoryName: String?
    var budgetName: String?
    var sourceName: String?
    var destinationName: String?
    var tags: [String]
    var notes: String?
    /// Firefly's recorded conversion when the transaction touches a second
    /// currency (e.g. transfers between accounts in different currencies).
    var foreignAmount: Decimal?
    var foreignCurrencyCode: String?

    init(journalID: String, groupID: String, date: Date, amount: Decimal,
         currencyCode: String, transactionDescription: String, type: String,
         categoryName: String?, budgetName: String?, sourceName: String?,
         destinationName: String?, tags: [String], notes: String? = nil,
         foreignAmount: Decimal? = nil, foreignCurrencyCode: String? = nil) {
        self.journalID = journalID
        self.groupID = groupID
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.transactionDescription = transactionDescription
        self.type = type
        self.categoryName = categoryName
        self.budgetName = budgetName
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.tags = tags
        self.notes = notes
        self.foreignAmount = foreignAmount
        self.foreignCurrencyCode = foreignCurrencyCode
    }

    var isExpense: Bool { type == "withdrawal" }
    var isIncome: Bool { type == "deposit" }

    /// Non-optional category, for display and sorting.
    var categoryLabel: String { categoryName ?? "Uncategorised" }

    /// Every available detail, for hover tooltips. Empty fields are skipped.
    var details: String {
        var lines: [String] = [
            transactionDescription,
            date.formatted(date: .long, time: .omitted),
            "\(type.capitalized) · \(amount.currency(currencyCode))",
        ]
        if let categoryName { lines.append("Category: \(categoryName)") }
        if let budgetName { lines.append("Budget: \(budgetName)") }
        if let sourceName { lines.append("From: \(sourceName)") }
        if let destinationName { lines.append("To: \(destinationName)") }
        if let foreignAmount, let foreignCurrencyCode {
            lines.append("Converted: \(foreignAmount.currency(foreignCurrencyCode))")
        }
        if !tags.isEmpty { lines.append("Tags: \(tags.joined(separator: ", "))") }
        if let notes, !notes.isEmpty { lines.append("Notes: \(notes)") }
        lines.append("Journal #\(journalID) · Group #\(groupID)")
        return lines.joined(separator: "\n")
    }
}

@Model
final class FFAccount {
    @Attribute(.unique) var accountID: String
    var name: String
    /// "asset", "expense", "revenue", "liabilities", ...
    var type: String
    var currentBalance: Decimal
    var currencyCode: String

    init(accountID: String, name: String, type: String,
         currentBalance: Decimal, currencyCode: String) {
        self.accountID = accountID
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.currencyCode = currencyCode
    }
}

/// A Firefly III piggy bank — a savings goal with a target amount.
@Model
final class FFPiggyBank {
    @Attribute(.unique) var piggyID: String
    var name: String
    var currentAmount: Decimal
    var targetAmount: Decimal
    var currencyCode: String
    /// The Firefly "object group" this piggy belongs to (e.g. "House"); nil = ungrouped.
    var objectGroup: String?
    /// Firefly's suggested monthly contribution to hit the target by its date; 0 when no date.
    /// Inline defaults are required so SwiftData can lightweight-migrate existing stores.
    var savePerMonth: Decimal = 0
    var startDate: Date?
    var targetDate: Date?
    /// Sort order within its group, and the group's own order, from Firefly.
    var order: Int = 0
    var groupOrder: Int = 0
    /// The asset account this piggy is attached to (Firefly links each piggy to one
    /// account). Optional → no inline default needed for lightweight migration.
    var accountID: String?
    var accountName: String?

    init(piggyID: String, name: String, currentAmount: Decimal,
         targetAmount: Decimal, currencyCode: String,
         objectGroup: String? = nil, savePerMonth: Decimal = 0,
         startDate: Date? = nil, targetDate: Date? = nil, order: Int = 0, groupOrder: Int = 0,
         accountID: String? = nil, accountName: String? = nil) {
        self.piggyID = piggyID
        self.name = name
        self.currentAmount = currentAmount
        self.targetAmount = targetAmount
        self.currencyCode = currencyCode
        self.objectGroup = objectGroup
        self.savePerMonth = savePerMonth
        self.startDate = startDate
        self.targetDate = targetDate
        self.order = order
        self.groupOrder = groupOrder
        self.accountID = accountID
        self.accountName = accountName
    }

    /// Remaining to reach the target (0 when met or no target).
    var leftToSave: Decimal { max(targetAmount - currentAmount, 0) }
    /// 0…1 progress toward the target; 0 when there's no target.
    var fraction: Double {
        targetAmount > 0 ? min((currentAmount / targetAmount).doubleValue, 1) : 0
    }
}

/// One Firefly III budget limit: the amount budgeted for a named budget over a
/// specific period. Spending against it is computed locally from transactions
/// (which already carry `budgetName`), so only the allocation is stored here.
@Model
final class FFBudgetLimit {
    @Attribute(.unique) var limitID: String
    var budgetID: String
    var budgetName: String
    var amount: Decimal
    var currencyCode: String
    var start: Date
    /// Inclusive last day of the budget period, as Firefly reports it.
    var end: Date

    init(limitID: String, budgetID: String, budgetName: String, amount: Decimal,
         currencyCode: String, start: Date, end: Date) {
        self.limitID = limitID
        self.budgetID = budgetID
        self.budgetName = budgetName
        self.amount = amount
        self.currencyCode = currencyCode
        self.start = start
        self.end = end
    }
}

/// Singleton-ish record tracking sync progress.
@Model
final class SyncState {
    var lastFullSync: Date?
    var lastRefresh: Date?

    init(lastFullSync: Date? = nil, lastRefresh: Date? = nil) {
        self.lastFullSync = lastFullSync
        self.lastRefresh = lastRefresh
    }
}
