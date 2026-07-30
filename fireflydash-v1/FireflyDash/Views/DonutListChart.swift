import SwiftUI
import Charts

/// Sure-style donut: the chart on the left, a category list (name, value,
/// % of total) on the right. Hovering a slice or a row highlights it and shows
/// its total in the centre of the ring; rows with a subcategory breakdown show
/// it in a hover tooltip. Optionally clickable (slices and rows).
struct DonutListChart: View {
    struct Slice: Identifiable {
        var id: String { label }
        let label: String
        let amount: Decimal
        let color: Color
        /// True when the amount combines more than one currency (shown as ≈).
        var mixed = false
        /// Multi-line subcategory breakdown shown when hovering the list row.
        var detail: String? = nil
    }

    let slices: [Slice]
    let currency: String
    let centerTitle: String
    let centerAmount: Decimal
    var centerApprox = false
    var onSelect: ((String) -> Void)? = nil
    @State private var hovered: String?

    private var total: Double {
        slices.reduce(0) { $0 + $1.amount.doubleValue }
    }

    /// "Sub — €123" lines for a slice's hover detail; nil when there are no subs.
    static func subDetail(_ subs: [(label: String, amount: Decimal)], currency: String) -> String? {
        guard !subs.isEmpty else { return nil }
        return subs.map { "\($0.label) — \($0.amount.currency(currency))" }.joined(separator: "\n")
    }

    var body: some View {
        // The list takes ~40% of the width (clamped) so the chart stays usable
        // whether it's full-width (Categories) or a half-width Dashboard card.
        GeometryReader { geo in
            let listWidth = min(max(geo.size.width * 0.4, 150), 300)
            HStack(alignment: .center, spacing: 20) {
                donutArea
                rowList
                    .frame(width: listWidth)
            }
        }
    }

    // MARK: donut

    private var donutArea: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2

            ZStack {
                Chart(slices) { s in
                    SectorMark(angle: .value("Amount", s.amount.doubleValue),
                               innerRadius: .ratio(0.62),
                               angularInset: 1.5)
                        .foregroundStyle(s.color.opacity(hovered == nil || hovered == s.label ? 1 : 0.3))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: side, height: side)
                .position(center)

                centerLabel
                    .frame(width: radius * 1.1)
                    .position(center)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = slice(at: location, center: center, radius: radius)
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture { location in
                slice(at: location, center: center, radius: radius)
                    .map { onSelect?($0) }
            }
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let hovered, let s = slices.first(where: { $0.label == hovered }), total > 0 {
            VStack(spacing: 2) {
                Text(s.label)
                    .appFont(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(s.amount.currency(currency, approx: s.mixed))
                    .appFont(.title, weight: .bold).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text((s.amount.doubleValue / total).formatted(.percent.precision(.fractionLength(1))))
                    .appFont(.title3, weight: .heavy).monospacedDigit()
            }
        } else {
            VStack(spacing: 2) {
                Text(centerTitle).appFont(.subheadline).foregroundStyle(.secondary)
                Text(centerAmount.currency(currency, approx: centerApprox))
                    .appFont(.title, weight: .bold).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }

    /// Which slice (if any) sits under a point on the ring.
    private func slice(at location: CGPoint, center: CGPoint, radius: CGFloat) -> String? {
        guard total > 0 else { return nil }
        let dx = location.x - center.x
        let dy = location.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist <= radius, dist >= radius * 0.55 else { return nil }
        var angle = atan2(Double(dx), Double(-dy))
        if angle < 0 { angle += 2 * .pi }
        var cumulative = 0.0
        for s in slices {
            cumulative += s.amount.doubleValue / total * 2 * .pi
            if angle <= cumulative { return s.label }
        }
        return nil
    }

    // MARK: list

    private var rowList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(slices) { s in
                    row(s)
                    if s.id != slices.last?.id {
                        Divider().padding(.leading, 22)
                    }
                }
            }
        }
    }

    private func row(_ s: Slice) -> some View {
        let fraction = total > 0 ? s.amount.doubleValue / total : 0
        return HStack(spacing: 8) {
            Circle().fill(s.color).frame(width: 8, height: 8)
            Text(s.label).lineLimit(1)
            Spacer(minLength: 8)
            Text(s.amount.currency(currency, approx: s.mixed)).monospacedDigit()
            Text(fraction.formatted(.percent.precision(.fractionLength(fraction < 0.01 && fraction > 0 ? 1 : 0))))
                .foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .appFont(.callout)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(hovered == s.label ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hovered = s.label
            } else if hovered == s.label {
                hovered = nil
            }
        }
        .onTapGesture { onSelect?(s.label) }
        .tooltip(s.detail)
    }
}
