import SwiftUI

/// Transaction list for the bottom half of a split view (Averages, Categories):
/// header with count + total, clickable sortable column headers, hover tooltips.
/// A List, not a Table: hover tooltips never fire inside NSTableView-backed
/// Table cells, so we lay the columns out ourselves and sort via the headers.
struct TransactionPane: View {
    let title: String
    let transactions: [FFTransaction]
    let currency: String
    @State private var sortOrder = [KeyPathComparator(\FFTransaction.date, order: .reverse)]

    private var sorted: [FFTransaction] { transactions.sorted(using: sortOrder) }

    /// Face-value sum; ≈ flags a total that combines more than one currency.
    private var totalLabel: String {
        let total = transactions.reduce(Decimal(0)) { $0 + $1.amount }
        let mixed = Set(transactions.map(\.currencyCode)).count > 1
        return total.currency(transactions.first?.currencyCode ?? currency, approx: mixed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .appFont(.headline)
                Spacer()
                Text("\(transactions.count) transaction\(transactions.count == 1 ? "" : "s") · \(totalLabel)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .readableWidth()
            Divider()
            HStack(spacing: 12) {
                sortHeader("Date", \.date)
                    .frame(width: 110, alignment: .leading)
                sortHeader("Description", \.transactionDescription)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortHeader("Category", \.categoryLabel)
                    .frame(width: 200, alignment: .leading)
                sortHeader("Amount", \.amount)
                    .frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .readableWidth()
            Divider()
            List(sorted) { t in
                HStack(spacing: 12) {
                    Text(t.date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(t.transactionDescription)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        CategoryBadge(category: t.categoryLabel, size: 18)
                        Text(t.categoryLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 200, alignment: .leading)
                    Text(t.amount.currency(t.currencyCode))
                        .monospacedDigit()
                        .frame(width: 110, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .tooltip(t.details)
                .readableWidth()
            }
            .listStyle(.plain)
        }
    }

    /// Column header that sorts by its key path; click again to flip order.
    private func sortHeader<V: Comparable & Sendable>(
        _ title: String, _ keyPath: KeyPath<FFTransaction, V> & Sendable) -> some View {
        let isActive = sortOrder.first?.keyPath == keyPath
        return Button {
            if isActive {
                let flipped: SortOrder = sortOrder[0].order == .forward ? .reverse : .forward
                sortOrder = [KeyPathComparator(keyPath, order: flipped)]
            } else {
                sortOrder = [KeyPathComparator(keyPath)]
            }
        } label: {
            HStack(spacing: 3) {
                Text(title).appFont(.caption, weight: isActive ? .semibold : .regular)
                if isActive {
                    Image(systemName: sortOrder[0].order == .forward ? "chevron.up" : "chevron.down")
                        .appFont(.caption2)
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Draggable divider between two vertically stacked panes. The caller resolves
/// the current top height and persists whatever the drag produces.
struct PaneDivider: View {
    let current: Double
    let range: ClosedRange<Double>
    let onDrag: (Double) -> Void
    @State private var dragBase: Double?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 7)
            .overlay(Divider())
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(
                // Global coordinates: the divider itself moves during the
                // drag, so local-space translations feed back into the height
                // and the divider judders. Global space keeps the reference
                // frame still.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragBase ?? current
                        dragBase = base
                        onDrag(min(max(base + value.translation.height, range.lowerBound), range.upperBound))
                    }
                    .onEnded { _ in dragBase = nil }
            )
    }
}
