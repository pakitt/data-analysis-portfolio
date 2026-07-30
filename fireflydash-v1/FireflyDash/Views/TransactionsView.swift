import SwiftUI
import SwiftData

/// Transactions grouped by month. Each month is a collapsed row showing the
/// net sum for that month; click to expand into the individual transactions.
struct TransactionsView: View {
    @Query(sort: \FFTransaction.date, order: .reverse) private var allTransactions: [FFTransaction]
    @State private var search = ""
    @State private var typeFilter: String? = nil
    @State private var expandedMonths: Set<Date> = []
    @State private var expandedYears: Set<Int> = []
    @State private var didSeedExpansion = false

    private var filtered: [FFTransaction] {
        Insights.visible(allTransactions).filter { t in
            (typeFilter == nil || t.type == typeFilter)
            && (search.isEmpty
                || t.transactionDescription.localizedCaseInsensitiveContains(search)
                || (t.categoryName ?? "").localizedCaseInsensitiveContains(search)
                || (t.destinationName ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    private struct MonthGroup: Identifiable {
        var id: Date { month }
        let month: Date
        /// Income/expense/transfers are kept separate — transfers move money
        /// between the user's own accounts, so lumping them into "income"
        /// (as the old single `total` did) badly inflates the year/month
        /// figure without meaning anything.
        let income: Decimal
        let expense: Decimal    // positive magnitude
        let transfers: Decimal  // positive magnitude
        let mixed: Bool
        let currency: String
        let items: [FFTransaction]
        var net: Decimal { income - expense }
    }

    private struct YearGroup: Identifiable {
        var id: Int { year }
        let year: Int
        let income: Decimal
        let expense: Decimal
        let transfers: Decimal
        let mixed: Bool
        let currency: String
        let months: [MonthGroup]
        var net: Decimal { income - expense }
    }

    /// Transactions grouped by year, then by month within each year.
    private var yearGroups: [YearGroup] {
        let cal = Calendar.current
        let base = Insights.baseCurrency(allTransactions)
        let conv = Insights.converter(for: allTransactions)
        let byMonth = Dictionary(grouping: filtered) { t in
            cal.date(from: cal.dateComponents([.year, .month], from: t.date))!
        }
        let monthGroups = byMonth.map { month, items -> MonthGroup in
            var income: Decimal = 0
            var expense: Decimal = 0
            var transfers: Decimal = 0
            var mixed = false
            for t in items {
                let (v, converted) = conv.value(t)
                if t.isIncome { income += v }
                else if t.isExpense { expense += v }
                else { transfers += v }
                if converted { mixed = true }
            }
            return MonthGroup(month: month, income: income, expense: expense, transfers: transfers,
                              mixed: mixed, currency: base, items: items.sorted { $0.date > $1.date })
        }
        let byYear = Dictionary(grouping: monthGroups) { cal.component(.year, from: $0.month) }
        return byYear.map { year, months -> YearGroup in
            YearGroup(year: year,
                      income: months.reduce(Decimal(0)) { $0 + $1.income },
                      expense: months.reduce(Decimal(0)) { $0 + $1.expense },
                      transfers: months.reduce(Decimal(0)) { $0 + $1.transfers },
                      mixed: months.contains { $0.mixed },
                      currency: base,
                      months: months.sorted { $0.month > $1.month })
        }
        .sorted { $0.year > $1.year }
    }

    private func isMonthExpanded(_ month: Date) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(month) },
            set: { open in
                if open { expandedMonths.insert(month) } else { expandedMonths.remove(month) }
            })
    }

    private func isYearExpanded(_ year: Int) -> Binding<Bool> {
        Binding(
            get: { expandedYears.contains(year) },
            set: { open in
                if open { expandedYears.insert(year) } else { expandedYears.remove(year) }
            })
    }

    /// Flat, date-sorted matches shown while a search is active — avoids
    /// re-diffing the nested disclosure outline (which SwiftUI crashes on when
    /// the data changes under a forced expansion).
    private var searchResults: [FFTransaction] {
        filtered.sorted { $0.date > $1.date }
    }

    var body: some View {
        // Swap the entire List (rather than switching content inside one List)
        // so SwiftUI replaces the view instead of diffing a nested outline
        // against the flat results — which is what crashed while searching.
        Group {
            if search.isEmpty {
                groupedList
            } else {
                flatList
            }
        }
        .searchable(text: $search, prompt: "Search description, category, payee")
        .toolbar {
            ToolbarItem {
                Picker("Type", selection: $typeFilter) {
                    Text("All").tag(String?.none)
                    Text("Expenses").tag(String?.some("withdrawal"))
                    Text("Income").tag(String?.some("deposit"))
                    Text("Transfers").tag(String?.some("transfer"))
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Transactions")
        .navigationSubtitle("\(filtered.count) shown")
    }

    private var groupedList: some View {
        List {
            ForEach(yearGroups) { yearGroup in
                DisclosureGroup(isExpanded: isYearExpanded(yearGroup.year)) {
                    ForEach(yearGroup.months) { group in
                        DisclosureGroup(isExpanded: isMonthExpanded(group.month)) {
                            ForEach(group.items) { t in
                                transactionRow(t)
                            }
                        } label: {
                            monthHeader(group)
                        }
                    }
                } label: {
                    yearHeader(yearGroup)
                }
            }
        }
        // Open the most recent year by default so the view isn't all collapsed.
        .onAppear {
            if !didSeedExpansion, let latest = yearGroups.first?.year {
                expandedYears.insert(latest)
                didSeedExpansion = true
            }
        }
    }

    private var flatList: some View {
        List(searchResults) { t in
            transactionRow(t)
        }
    }

    /// Compact "label above value" stat, used in the year/month header rows.
    /// Fixed-width so the same column (Income/Expenses/Net/Transfers) lands
    /// at the same x position on every row — always shown (Transfers reads
    /// "€0" rather than disappearing) so rows with no transfers don't shift
    /// every other column rightward relative to rows that have some.
    private func stat(_ title: String, _ value: Decimal, currency: String, mixed: Bool,
                      color: Color, valueStyle: Font.TextStyle, valueWeight: Font.Weight, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).appFont(.caption2).foregroundStyle(.secondary)
            Text(value.currency(currency, approx: mixed))
                .appFont(valueStyle, weight: valueWeight)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: width, alignment: .trailing)
    }

    private func yearHeader(_ group: YearGroup) -> some View {
        HStack(spacing: 18) {
            Text(String(group.year))
                .appFont(.title3, weight: .bold)
                .monospacedDigit()
            Spacer()
            stat("Income", group.income, currency: group.currency, mixed: group.mixed,
                 color: .green, valueStyle: .subheadline, valueWeight: .semibold, width: 100)
            stat("Expenses", group.expense, currency: group.currency, mixed: group.mixed,
                 color: .primary, valueStyle: .subheadline, valueWeight: .semibold, width: 100)
            stat("Net", group.net, currency: group.currency, mixed: group.mixed,
                 color: group.net >= 0 ? .green : .red, valueStyle: .title3, valueWeight: .bold, width: 110)
            stat("Transfers", group.transfers, currency: group.currency, mixed: group.mixed,
                 color: .secondary, valueStyle: .subheadline, valueWeight: .semibold, width: 100)
        }
        .padding(.vertical, 4)
        .readableWidth()
    }

    private func monthHeader(_ group: MonthGroup) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Text(group.month.formatted(.dateTime.month(.wide)))
                    .appFont(.headline)
                Text("\(group.items.count) transactions")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stat("Income", group.income, currency: group.currency, mixed: group.mixed,
                 color: .green, valueStyle: .callout, valueWeight: .medium, width: 100)
            stat("Expenses", group.expense, currency: group.currency, mixed: group.mixed,
                 color: .primary, valueStyle: .callout, valueWeight: .medium, width: 100)
            stat("Net", group.net, currency: group.currency, mixed: group.mixed,
                 color: group.net >= 0 ? .green : .red, valueStyle: .headline, valueWeight: .semibold, width: 110)
            stat("Transfers", group.transfers, currency: group.currency, mixed: group.mixed,
                 color: .secondary, valueStyle: .callout, valueWeight: .medium, width: 100)
        }
        .padding(.vertical, 4)
        .readableWidth()
    }

    private func transactionRow(_ t: FFTransaction) -> some View {
        HStack(spacing: 12) {
            CategoryBadge(category: t.categoryName ?? "Uncategorised", size: 20)
            Text(t.date.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(.secondary)
                .frame(width: 95, alignment: .leading)
            Text(t.transactionDescription)
                .lineLimit(1)
            Spacer()
            Text(t.categoryName ?? "—")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)
            Text(t.isExpense ? (t.sourceName ?? "—") : (t.destinationName ?? "—"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text((t.isExpense ? -t.amount : t.amount).currency(t.currencyCode))
                .monospacedDigit()
                .foregroundStyle(t.isExpense ? .primary : (t.isIncome ? Color.green : Color.secondary))
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .tooltip(t.details)
        .readableWidth()
    }
}
