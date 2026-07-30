import Foundation
import SwiftData
import AppKit

/// Exports a self-contained HTML snapshot of the dashboard into a user-chosen
/// folder (typically inside iCloud Drive), so it can be viewed on an iPhone
/// without a native iOS app — open it from the Files app or a tiny Shortcut.
///
/// The file embeds everything (inline CSS, CSS-only charts, no external assets
/// or network), so it renders offline once iCloud has synced it to the phone.
/// All figures are computed here with the same `Insights`/`CurrencyConverter`
/// helpers the macOS UI uses, so the phone shows the same numbers.
///
/// Access to the folder is a free, sandbox-friendly path: the user picks it once
/// (`com.apple.security.files.user-selected.read-write`) and we persist a
/// security-scoped bookmark — no iCloud-container entitlement, so no paid
/// Apple Developer Program membership is required.
/// Not actor-isolated: every member here is a pure computation over Foundation
/// values or plain file I/O, safe to run on a background actor (the sync
/// engine calls `export(context:)` from its background `SyncActor` so writing
/// an 18-panel HTML snapshot after every sync doesn't block the main thread).
/// The one exception is `chooseFolder()`, which drives `NSOpenPanel` and must
/// run on the main thread — it's annotated `@MainActor` individually.
enum WebExport {
    static let bookmarkKey = "iphoneExportBookmark"
    static let folderPathKey = "iphoneExportFolderPath"
    static let lastExportKey = "iphoneExportLastTS"
    static let autoExportKey = "iphoneExportAfterSync"
    static let fileName = "FireflyDash.html"

    enum ExportError: LocalizedError {
        case noFolder, accessDenied
        var errorDescription: String? {
            switch self {
            case .noFolder: "No export folder chosen yet."
            case .accessDenied: "Couldn't access the chosen folder — pick it again."
            }
        }
    }

    // MARK: - Folder selection & access

    /// A friendly display name for the chosen folder, or nil when none is set.
    static var chosenFolderPath: String? {
        UserDefaults.standard.string(forKey: folderPathKey)
    }

    static var lastExport: Date? {
        let ts = UserDefaults.standard.double(forKey: lastExportKey)
        return ts == 0 ? nil : Date(timeIntervalSinceReferenceDate: ts)
    }

    /// Prompt the user to pick an export folder and persist a security-scoped
    /// bookmark to it. Returns true when a folder was chosen.
    @MainActor
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Pick a folder inside iCloud Drive (e.g. a new “FireflyDash” folder) to export the iPhone dashboard into."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            UserDefaults.standard.set(url.path(percentEncoded: false), forKey: folderPathKey)
            return true
        } catch {
            return false
        }
    }

    /// Resolve the bookmarked folder, refreshing the bookmark if it went stale.
    private static func resolveFolder() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { throw ExportError.noFolder }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, url.startAccessingSecurityScopedResource() {
            if let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                 includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    // MARK: - Export

    @discardableResult
    static func export(context: ModelContext) -> Result<URL, Error> {
        do {
            let folder = try resolveFolder()
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            guard accessing else { throw ExportError.accessDenied }

            let html = try buildHTML(context: context)
            let fileURL = folder.appending(path: fileName)
            try Data(html.utf8).write(to: fileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: lastExportKey)
            return .success(fileURL)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Data → HTML

    /// Distinct hex palette, assigned to categories in descending-amount order.
    private static let palette = [
        "#0a84ff", "#ff9f0a", "#30d158", "#ff375f", "#bf5af2", "#40c8e0",
        "#ff453a", "#ffd60a", "#5e5ce6", "#66d4cf", "#ac8e68", "#64d2ff",
        "#cc8800", "#0a76d6", "#d6008a", "#7aa800",
    ]

    private static func fmt(_ v: Decimal, _ code: String, approx: Bool = false) -> String {
        (approx ? "≈" : "") + v.currency(code)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One selectable timeframe: a CSS-safe slug, a button label, the window,
    /// and how its heading/trend should read. Built from FlowRange plus a
    /// computed "Payday" window (since the last detected paycheck).
    ///
    /// The toggle is pure HTML/CSS (radio inputs + labels + `:checked` sibling
    /// rules) — iOS Quick Look renders the HTML but does NOT run JavaScript, so
    /// every range is rendered server-side and CSS reveals the selected panel.
    private struct RangeSpec {
        let slug: String, label: String
        let start: Date, end: Date
        let monthHeading: Bool   // "can save"/"over by" vs "saved"/"overspent by"
        let periodLabel: String
        let trendCount: Int      // months shown in the trend chart
        let avgMonthCount: Int   // complete past months the averages cover
        let avgSubtitle: String
        let allTime: Bool
        /// Only set for "Payday": the estimated next paycheck — the full
        /// projected period end (not just "today", which `end` stops at).
        /// Drives the same essentials/piggy/external-savings projection the
        /// Mac Dashboard and menu-bar widget use for their Payday figure, so
        /// this matches them instead of showing a naive income-minus-spent
        /// total that ignores bills not yet paid.
        let projectionEnd: Date?
    }

    /// Render-ready strings for one timeframe (all computed in Swift).
    private struct RangePayload {
        let slug: String
        let heading: String, period: String, pos: Bool
        let income: String, spent: String, surplus: String
        let gradient: String, legendHTML: String
        let trendTitle: String, trendAvg: String, barsHTML: String
        /// Essentials/piggy/external-savings breakdown rows, when projected
        /// (empty string otherwise).
        let commitmentHTML: String
    }

    /// One amortisation mode: a CSS-safe slug, a button label, the transaction
    /// source it draws from, and a converter for that source.
    private struct AmortMode {
        let slug: String, label: String
        let source: [FFTransaction]
        let conv: CurrencyConverter
    }

    private static func buildHTML(context: ModelContext) throws -> String {
        let all = try context.fetch(
            FetchDescriptor<FFTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let visible = Insights.visible(all)
        let accounts = try context.fetch(FetchDescriptor<FFAccount>())
        let piggies = try context.fetch(FetchDescriptor<FFPiggyBank>())

        let base = Insights.baseCurrency(visible)
        let externalMonthlySavings = UserDefaults.standard.double(forKey: AppSettings.key("externalMonthlySavings"))
        let updated = Date().formatted(date: .abbreviated, time: .shortened)

        guard !visible.isEmpty else {
            return shell(title: "FireflyDash", updated: updated,
                         body: "<div class='empty'>No data yet. Sync FireflyDash on your Mac, then export again.</div>")
        }

        let subThreshold = UserDefaults.standard.object(forKey: "subThresholdPercent") as? Double ?? 2.0
        let specs = rangeSpecs(visible: visible)
        // Two independent CSS-only toggles: amortisation × timeframe. "Actual"
        // counts each expense in the month it was paid; "Amortised" spreads
        // `spreadN`-tagged lumps across N months (matches the Mac toggle) — so a
        // figure can be reconciled with the desktop in whichever mode it's in.
        let amortised = Insights.entries(all, amortize: true)
        let amorts = [
            AmortMode(slug: "act", label: "Actual", source: visible,
                      conv: Insights.converter(for: visible)),
            AmortMode(slug: "amo", label: "Amortised", source: amortised,
                      conv: Insights.converter(for: amortised)),
        ]
        let aside = savingsAside(accounts: accounts, piggies: piggies,
                                 conv: amorts[0].conv, base: base)

        var radios = "", amRow = "", rangeRow = "", panels = "", tabCSS = ""
        for (i, am) in amorts.enumerated() {
            radios += "<input class=\"tabin\" type=\"radio\" name=\"am\" id=\"am-\(am.slug)\"\(i == 0 ? " checked" : "")>"
            amRow += "<label for=\"am-\(am.slug)\">\(esc(am.label))</label>"
            tabCSS += "#am-\(am.slug):checked~.amrow label[for=\"am-\(am.slug)\"]{background:var(--amber);color:#0b1220;border-color:var(--amber)}"
        }
        for (i, spec) in specs.enumerated() {
            radios += "<input class=\"tabin\" type=\"radio\" name=\"rg\" id=\"t-\(spec.slug)\"\(i == 0 ? " checked" : "")>"
            rangeRow += "<label for=\"t-\(spec.slug)\">\(esc(spec.label))</label>"
            tabCSS += "#t-\(spec.slug):checked~.ranges label[for=\"t-\(spec.slug)\"]{background:var(--amber);color:#0b1220;border-color:var(--amber)}"
        }
        for am in amorts {
            for spec in specs {
                let rp = payload(spec: spec, source: am.source, allTransactions: all,
                                 piggies: piggies, externalMonthlySavings: externalMonthlySavings,
                                 conv: am.conv, base: base, subThreshold: subThreshold)
                let cls = "p-\(am.slug)-\(spec.slug)"
                panels += "<div class=\"panel \(cls)\">"
                panels += heroSection(rp: rp, aside: aside)
                panels += categorySection(rp: rp)
                panels += trendSection(rp: rp)
                panels += averagesSection(spec: spec, source: am.source, conv: am.conv, base: base)
                panels += "</div>"
                // Reveal a panel only when BOTH its amortise mode and its range
                // are checked (chained `:checked ~` sibling selectors).
                tabCSS += "#am-\(am.slug):checked~#t-\(spec.slug):checked~.panels .\(cls){display:block}"
            }
        }

        var html = "<style>\(tabCSS)</style>"
        html += radios
        html += "<div class=\"amrow\">\(amRow)</div>"
        html += "<div class=\"ranges\">\(rangeRow)</div>"
        html += "<div class=\"panels\">\(panels)</div>"
        html += piggySection(piggies: piggies, conv: amorts[0].conv, base: base)
        html += transactionsSection(visible: visible, conv: amorts[0].conv, base: base)

        return shell(title: "FireflyDash", updated: updated, body: html)
    }

    // MARK: Per-timeframe computation

    /// The timeframes offered: "Payday" first (when a paycheck is detected),
    /// then the Dashboard's FlowRange set (minus the macOS-only Custom range).
    private static func rangeSpecs(visible: [FFTransaction]) -> [RangeSpec] {
        var specs: [RangeSpec] = []
        // "Payday": since the most recent detected paycheck → end of today —
        // answers "what have we spent since we were last paid?". Its averages
        // fall back to a 3-complete-month baseline (a partial period has none).
        if let lastPay = visible.filter(Insights.isPaycheck).map(\.date).max() {
            // The WHOLE day the paycheck lands — the transaction's time-of-day is
            // meaningless (Enable Banking imports carry none), so snap to the
            // start of that day; otherwise same-day spending before the paycheck's
            // timestamp is wrongly excluded.
            let start = Calendar.current.startOfDay(for: lastPay)
            let end = Calendar.current.date(byAdding: .day, value: 1,
                                            to: Calendar.current.startOfDay(for: Date()))!
            // Same start-of-day normalisation as the Mac's `projectionHorizonEnd`
            // — imported transactions occasionally carry a stray non-midnight
            // time, which would otherwise skew the estimate by a few hours.
            let projectionEnd = Insights.nextPaycheckEstimate(after: start, in: visible)
            specs.append(RangeSpec(
                slug: "pay", label: "Payday", start: start, end: end, monthHeading: true,
                periodLabel: "Since \(start.formatted(.dateTime.day().month(.abbreviated)))",
                trendCount: 12, avgMonthCount: 3,
                avgSubtitle: "Average over 3 complete months", allTime: false,
                projectionEnd: projectionEnd))
        }
        let ranges: [FlowRange] = [.month, .threeMonths, .sixMonths, .ytd, .qtd, .year, .fiveYears, .all]
        for r in ranges {
            let (start, end) = r.window
            let n = avgMonthCount(r, visible: visible)
            specs.append(RangeSpec(
                slug: slug(r), label: r.rawValue, start: start, end: end,
                monthHeading: r == .month,
                periodLabel: periodLabel(range: r, start: start, end: end),
                trendCount: trendCount(r, visible: visible), avgMonthCount: n,
                avgSubtitle: avgSubtitle(range: r, months: n), allTime: r == .all,
                projectionEnd: nil))
        }
        return specs
    }

    private static func slug(_ r: FlowRange) -> String {
        r.rawValue.lowercased()   // "3M"→"3m", "YTD"→"ytd", … (valid in "t-…" ids)
    }

    private static func payload(spec: RangeSpec, source: [FFTransaction], allTransactions: [FFTransaction],
                                piggies: [FFPiggyBank], externalMonthlySavings: Double,
                                conv: CurrencyConverter, base: String,
                                subThreshold: Double) -> RangePayload {
        let ins = Insights.range(start: spec.start, end: spec.end, in: source, converter: conv)

        // Only "Payday" projects forward — mirrors the Mac Dashboard's
        // `range == .payday` gate (Month and every other range just show the
        // plain income-minus-spent delta, same as before).
        var displaySurplus = ins.surplus
        var displayMixed = ins.mixed
        var heading: String
        var commitmentHTML = ""
        if let projectionEnd = spec.projectionEnd {
            let window = (spec.start, projectionEnd)
            // Essentials detection always runs on real (non-amortised) dates,
            // independent of which amortise panel this is — same as Dashboard.
            let projection = Insights.essentialProjection(window: window, asOf: Date(), in: allTransactions)
            // Shares the Mac Dashboard's frozen per-piggy tracking (see
            // PiggyProgress) so this figure always agrees with it, instead of
            // independently re-deriving a fresh total from scratch.
            let snapshotKey = AppSettings.key("piggyPeriodSnapshot")
            let snapshotRaw = UserDefaults.standard.string(forKey: snapshotKey) ?? ""
            let piggyResult = PiggyProgress.commitment(piggyBanks: piggies, window: window,
                                                       rawSnapshot: snapshotRaw, converter: conv)
            if piggyResult.rawSnapshot != snapshotRaw {
                UserDefaults.standard.set(piggyResult.rawSnapshot, forKey: snapshotKey)
            }
            let piggyAmount = piggyResult.commitment?.amount ?? 0
            let piggyMixed = piggyResult.commitment?.mixed ?? false
            var externalAmount: Decimal = 0
            if externalMonthlySavings > 0 {
                let days = Double(Calendar.current.dateComponents([.day], from: window.0, to: window.1).day ?? 30)
                externalAmount = Decimal(externalMonthlySavings) * Decimal(days / 30.4)
            }
            let essentialRemaining = projection.expectedRemaining
            let totalCommitment = essentialRemaining + piggyAmount + externalAmount
            displaySurplus = ins.surplus - totalCommitment
            displayMixed = ins.mixed || projection.mixed || piggyMixed

            if totalCommitment > 0 {
                heading = displaySurplus >= 0
                    ? "From the last paycheck you can safely save or spend up to"
                    : "You're projected to be over by"
                var rows = ""
                if essentialRemaining > 0 {
                    rows += "<div class=\"commit-row\"><span>📅 Essentials still due</span><b>\(fmt(essentialRemaining, base, approx: projection.mixed))</b></div>"
                }
                if piggyAmount > 0 {
                    rows += "<div class=\"commit-row\"><span>🐷 Piggy banks this period</span><b>\(fmt(piggyAmount, base, approx: piggyMixed))</b></div>"
                }
                if externalAmount > 0 {
                    rows += "<div class=\"commit-row\"><span>🔒 External savings</span><b>\(fmt(externalAmount, base))</b></div>"
                }
                commitmentHTML = "<div class=\"commit\">\(rows)</div>"
            } else {
                heading = displaySurplus >= 0 ? "You can save" : "You are over by"
            }
        } else {
            let pos = ins.surplus >= 0
            // Open windows (current month) look forward ("can save"); longer/
            // closed windows report what already happened ("saved").
            heading = spec.monthHeading
                ? (pos ? "You can save" : "You are over by")
                : (pos ? "You saved" : "You overspent by")
        }
        let pos = displaySurplus >= 0

        let mains = Insights.collapseSmall(
            Insights.mainBreakdown(ins.byCategory, mixedCategories: ins.byCategoryMixed),
            thresholdPercent: subThreshold)
        let donut = donutData(mains: mains, base: base)
        let bars = barsData(series: Insights.monthlySeries(count: spec.trendCount, in: source), base: base)
        let trendTitle = spec.allTime ? "Spending · all time" : "Spending · last \(spec.trendCount) months"

        return RangePayload(
            slug: spec.slug,
            heading: heading, period: spec.periodLabel, pos: pos,
            income: fmt(ins.income, base, approx: ins.mixed),
            spent: fmt(ins.spent, base, approx: ins.mixed),
            surplus: fmt(abs(displaySurplus), base, approx: displayMixed),
            gradient: donut.gradient, legendHTML: donut.html,
            trendTitle: trendTitle, trendAvg: bars.avgStr, barsHTML: bars.html,
            commitmentHTML: commitmentHTML)
    }

    /// How many trailing months the trend chart shows for a range — mirrors
    /// the Dashboard's TrendCard (short scopes keep a 12-month context).
    private static func trendCount(_ range: FlowRange, visible: [FFTransaction]) -> Int {
        switch range {
        case .month, .ytd, .qtd, .year, .custom, .payday: 12
        case .threeMonths: 3
        case .sixMonths: 6
        case .fiveYears: 60
        case .all:
            (Calendar.current.dateComponents([.month],
                from: Insights.monthStart(visible.map(\.date).min() ?? Date()),
                to: Insights.monthStart(Date())).month ?? 0) + 1
        }
    }

    private static func periodLabel(range: FlowRange, start: Date, end: Date) -> String {
        if range == .all { return "All time" }
        if range == .month { return start.formatted(.dateTime.month(.wide).year()) }
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: end)!
        return "\(start.formatted(.dateTime.month(.abbreviated).year())) – \(lastDay.formatted(.dateTime.month(.abbreviated).year()))"
    }

    /// Donut gradient + legend HTML for a set of main-category totals.
    private static func donutData(mains: [Insights.MainEntry], base: String)
        -> (gradient: String, html: String) {
        guard !mains.isEmpty else {
            return ("var(--line) 0% 100%",
                    "<div class=\"leg-row\" style=\"color:var(--dim)\">No spending in this period.</div>")
        }
        let total = mains.reduce(Decimal(0)) { $0 + $1.amount }
        var stops: [String] = []
        var html = ""
        var cursor = 0.0
        for (i, m) in mains.enumerated() {
            let color = palette[i % palette.count]
            let pct = total > 0 ? (m.amount / total).doubleValue * 100 : 0
            let start = cursor; cursor += pct
            stops.append("\(color) \(start)% \(cursor)%")
            let name = esc(m.main), amt = fmt(m.amount, base, approx: m.mixed), p = Int(pct.rounded())
            html += "<div class=\"leg-row\"><span class=\"dot\" style=\"background:\(color)\"></span>"
            html += "<span class=\"leg-name\">\(name)</span><span class=\"leg-amt\">\(amt)</span>"
            html += "<span class=\"leg-pct\">\(p)%</span></div>"
        }
        return (stops.joined(separator: ", "), html)
    }

    /// The full trend chart (left Y-axis with currency ticks, gridlines, bars,
    /// a dashed average line, and an X-axis of month initials) + the average
    /// footnote string. Bars are scaled to a "nice" rounded ceiling so the
    /// gridline labels are meaningful round numbers.
    private static func barsData(series: [MonthInsights], base: String)
        -> (avgStr: String, html: String) {
        let plotH = 120.0
        let maxSpent = series.map { $0.spent.doubleValue }.max() ?? 0
        let avg = Insights.average(series.map(\.spent))
        let top = niceMax(maxSpent)
        let denom = top > 0 ? top : 1

        var bars = "", labels = ""
        for m in series {
            let v = m.spent.doubleValue
            let h = v > 0 ? max(v / denom * plotH, 2) : 0
            let label = esc(m.month.formatted(.dateTime.month(.narrow)))
            let tip = esc("\(m.month.formatted(.dateTime.month(.abbreviated).year())): \(fmt(m.spent, base, approx: m.mixed))")
            bars += "<div class=\"bar-col\" title=\"\(tip)\"><div class=\"bar\(m.spent > avg ? " hot" : "")\""
            bars += " style=\"height:\(Int(h))px\"></div></div>"
            labels += "<span>\(label)</span>"
        }
        // Dashed average line, positioned from the baseline (only when in range).
        let avgY = min(avg.doubleValue / denom * plotH, plotH)
        let avgLine = avg > 0 ? "<div class=\"avgline\" style=\"bottom:\(Int(avgY))px\"></div>" : ""

        let chart = """
        <div class="trend-chart">
          <div class="yaxis">\
        <span>\(compactCurrency(Decimal(top), base))</span>\
        <span>\(compactCurrency(Decimal(top / 2), base))</span>\
        <span>\(compactCurrency(0, base))</span></div>
          <div class="plot">
            <div class="bars">\(avgLine)\(bars)</div>
            <div class="xlabels">\(labels)</div>
          </div>
        </div>
        """
        return ("avg \(fmt(avg, base))/mo", chart)
    }

    /// Round a maximum up to a tidy axis ceiling (half-magnitude steps):
    /// 4 900 → 5 000, 3 360 → 3 500, 420 → 450.
    private static func niceMax(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let mag = pow(10.0, floor(log10(x)))
        let step = mag / 2
        return (x / step).rounded(.up) * step
    }

    /// The base currency's symbol, derived from how it formats a zero ("€0"→"€").
    private static func currencySymbol(_ base: String) -> String {
        (0 as Decimal).currency(base).filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
    }

    /// Compact axis label: "€5k", "€3.5k", or "€450".
    private static func compactCurrency(_ v: Decimal, _ base: String) -> String {
        let sym = currencySymbol(base)
        let d = v.doubleValue
        if d >= 1000 {
            return "\(sym)\((d / 1000).formatted(.number.precision(.fractionLength(0...1))))k"
        }
        return "\(sym)\(Int(d.rounded()))"
    }

    /// Complete past months an average covers for a range — mirrors the Mac
    /// AveragesView's monthCount (the current, in-progress month is excluded).
    private static func avgMonthCount(_ range: FlowRange, visible: [FFTransaction]) -> Int {
        let cal = Calendar.current
        let thisMonth = Insights.monthStart(Date())
        switch range {
        case .month: return 1
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .year: return 12
        case .fiveYears: return 60
        case .ytd: return max(cal.component(.month, from: thisMonth) - 1, 1)
        case .qtd:
            let inQuarter = (cal.component(.month, from: thisMonth) - 1) % 3
            return inQuarter == 0 ? 3 : inQuarter
        case .all:
            guard let earliest = visible.map(\.date).min() else { return 6 }
            let lastComplete = cal.date(byAdding: .month, value: -1, to: thisMonth)!
            let diff = cal.dateComponents([.month], from: Insights.monthStart(earliest),
                                          to: lastComplete).month ?? 0
            return max(diff + 1, 1)
        case .custom, .payday: return 6
        }
    }

    private static func avgSubtitle(range: FlowRange, months: Int) -> String {
        let plural = months == 1 ? "" : "s"
        switch range {
        case .all: return "All \(months) complete months"
        case .ytd: return "Year to date — \(months) complete month\(plural)"
        case .qtd: return "Quarter to date — \(months) complete month\(plural)"
        default: return "Average over \(months) complete month\(plural)"
        }
    }

    // MARK: Sections

    /// Saved-so-far + piggy fulfilment (current state — not range-dependent),
    /// mirroring the Dashboard hero's right-hand panel.
    private static func savingsAside(accounts: [FFAccount], piggies: [FFPiggyBank],
                                     conv: CurrencyConverter, base: String) -> String {
        let savingsSel = Set((UserDefaults.standard.string(forKey: AppSettings.key("savingsAccountIDs")) ?? "")
            .split(separator: "\n").map(String.init))
        let selected = accounts.filter { savingsSel.contains($0.accountID) }
        var saved: Decimal = 0
        var savedMixed = false
        for a in selected {
            let (v, c) = conv.convert(a.currentBalance, from: a.currencyCode)
            saved += v; if c { savedMixed = true }
        }
        var piggyCurrent: Decimal = 0
        var piggyTarget: Decimal = 0
        var piggyMixed = false
        for p in piggies {
            let (c, cc) = conv.convert(p.currentAmount, from: p.currencyCode)
            let (t, tc) = conv.convert(p.targetAmount, from: p.currencyCode)
            piggyCurrent += c; piggyTarget += t
            if cc || tc { piggyMixed = true }
        }
        let fulfilment = piggyTarget > 0 ? min((piggyCurrent / piggyTarget).doubleValue, 1) : nil

        var aside = ""
        if !selected.isEmpty {
            aside += "<div class='hero-aside-row'><span class='lbl'>Saved so far</span>"
            aside += "<span class='val'>\(fmt(saved, base, approx: savedMixed))</span></div>"
        }
        if let f = fulfilment {
            let pct = Int((f * 100).rounded())
            aside += "<div class='ring' style='--pct:\(pct)'>"
            aside += "<div class='ring-inner'>\(f >= 1 ? "🎉" : "🐷")<span>\(pct)%</span></div></div>"
            aside += "<div class='hero-aside-row sub'>\(fmt(piggyCurrent, base, approx: piggyMixed)) of \(fmt(piggyTarget, base, approx: piggyMixed)) piggy goals</div>"
        }
        return aside
    }

    private static func heroSection(rp: RangePayload, aside: String) -> String {
        """
        <section class="hero \(rp.pos ? "pos" : "neg")">
          <div class="hero-main">
            <div class="hero-period">\(esc(rp.period))</div>
            <div class="hero-head">\(rp.heading)</div>
            <div class="hero-big">\(rp.surplus)</div>
            <div class="pills">
              <div class="pill"><span>Income</span><b>\(rp.income)</b></div>
              <div class="pill"><span>Spent</span><b>\(rp.spent)</b></div>
            </div>
            \(rp.commitmentHTML)
          </div>
          \(aside.isEmpty ? "" : "<div class='hero-aside'>\(aside)</div>")
        </section>
        """
    }

    private static func categorySection(rp: RangePayload) -> String {
        """
        <section class="card">
          <h2>Where the money went</h2>
          <div class="donut-wrap">
            <div class="donut" style="background:conic-gradient(\(rp.gradient))">
              <div class="donut-hole">
                <span class="donut-cap">Spent</span>
                <b>\(rp.spent)</b>
              </div>
            </div>
            <div class="legend">\(rp.legendHTML)</div>
          </div>
        </section>
        """
    }

    private static func trendSection(rp: RangePayload) -> String {
        """
        <section class="card">
          <h2>\(rp.trendTitle)</h2>
          \(rp.barsHTML)
          <div class="bars-foot">\(rp.trendAvg)</div>
        </section>
        """
    }

    /// One row of the averages table.
    private struct AvgRow {
        let main: String
        let average: Decimal, last30: Decimal, thisMonth: Decimal
        let avgMixed: Bool, last30Mixed: Bool, thisMonthMixed: Bool
        /// Last 30 days vs the monthly average, as a signed fraction.
        var delta: Double {
            if average == 0 { return last30 > 0 ? .infinity : 0 }
            return ((last30 - average) / average).doubleValue
        }
    }

    /// Per-main-category monthly averages over the range's complete months,
    /// alongside last-30-days and this-month-so-far — a phone-sized recreation
    /// of the Mac Averages view (main categories only; sorted by average).
    private static func averagesSection(spec: RangeSpec, source: [FFTransaction],
                                        conv: CurrencyConverter, base: String) -> String {
        let past = Array(Insights.monthlySeries(count: spec.avgMonthCount + 1, in: source).dropLast())
        var categories = Set<String>()
        for m in past { categories.formUnion(m.byCategory.map(\.category)) }

        let monthStart = Insights.monthStart(Date())
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!
        var thisMonth: [String: Decimal] = [:]
        var thisMonthMixed = Set<String>()
        for t in source where t.isExpense && t.date >= monthStart && t.date < nextMonth {
            let (v, c) = conv.value(t)
            thisMonth[t.categoryLabel, default: 0] += v
            if c { thisMonthMixed.insert(t.categoryLabel) }
            categories.insert(t.categoryLabel)
        }
        // Upper-bound at now: under amortisation a spreadN lump becomes N
        // forward-dated slivers, so without it the future slivers would all be
        // counted, inflating the figure back to the full lump.
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        var last30: [String: Decimal] = [:]
        var last30Mixed = Set<String>()
        for t in source where t.isExpense && t.date >= cutoff && t.date <= now {
            let (v, c) = conv.value(t)
            last30[t.categoryLabel, default: 0] += v
            if c { last30Mixed.insert(t.categoryLabel) }
            categories.insert(t.categoryLabel)
        }
        func monthValues(_ category: String) -> [Decimal] {
            past.map { $0.byCategory.first { $0.category == category }?.amount ?? 0 }
        }

        // Group full "Main:Sub" names under their main; the parent average sums
        // members month-by-month (exact), like the Mac.
        let byMain = Dictionary(grouping: categories) { Insights.splitCategory($0).main }
        var rows: [AvgRow] = []
        for (main, names) in byMain {
            let summed = (0..<past.count).map { i in names.reduce(Decimal(0)) { $0 + monthValues($1)[i] } }
            let avg = Insights.average(summed)
            let l30 = names.reduce(Decimal(0)) { $0 + (last30[$1] ?? 0) }
            let tm = names.reduce(Decimal(0)) { $0 + (thisMonth[$1] ?? 0) }
            if avg == 0 && l30 == 0 && tm == 0 { continue }
            rows.append(AvgRow(
                main: main, average: avg, last30: l30, thisMonth: tm,
                avgMixed: names.contains { n in past.contains { $0.byCategoryMixed.contains(n) } },
                last30Mixed: names.contains { last30Mixed.contains($0) },
                thisMonthMixed: names.contains { thisMonthMixed.contains($0) }))
        }
        rows.sort { $0.average > $1.average }

        var body = ""
        if rows.isEmpty {
            body = "<div class=\"avg-empty\">No spending in this window.</div>"
        } else {
            var tr = ""
            for r in rows {
                tr += "<tr><td class=\"avg-cat\"><span class=\"dot\" style=\"background:\(hashColor(r.main))\"></span>\(esc(r.main))</td>"
                tr += "<td>\(fmt(r.average, base, approx: r.avgMixed))</td>"
                tr += "<td>\(fmt(r.last30, base, approx: r.last30Mixed))</td>"
                tr += "<td>\(deltaCell(r))</td>"
                tr += "<td>\(fmt(r.thisMonth, base, approx: r.thisMonthMixed))</td></tr>"
            }
            body = """
            <div class="avg-wrap"><table class="avg">
            <thead><tr><th>Category</th><th>Avg/mo</th><th>30 d</th><th>vs</th><th>This mo</th></tr></thead>
            <tbody>\(tr)</tbody></table></div>
            """
        }
        return """
        <section class="card">
          <h2>Monthly averages</h2>
          <div class="avg-sub">\(esc(spec.avgSubtitle))</div>
          \(body)
        </section>
        """
    }

    /// "vs avg" cell: ↑ red = spending more than usual, ↓ green = less.
    private static func deltaCell(_ r: AvgRow) -> String {
        if r.average == 0 && r.last30 == 0 { return "<span class=\"d-flat\">—</span>" }
        if r.average == 0 { return "<span class=\"d-up\">↑ new</span>" }
        let pct = Int((abs(r.delta) * 100).rounded())
        if r.last30 == r.average { return "<span class=\"d-flat\">— \(pct)%</span>" }
        let up = r.last30 > r.average
        return "<span class=\"\(up ? "d-up" : "d-down")\">\(up ? "↑" : "↓") \(pct)%</span>"
    }

    /// Stable per-category colour for the averages dots (djb2 into the palette).
    private static func hashColor(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    private static func piggySection(piggies: [FFPiggyBank], conv: CurrencyConverter,
                                     base: String) -> String {
        guard !piggies.isEmpty else { return "" }
        // Group by object group, ordered as Firefly orders them.
        let grouped = Dictionary(grouping: piggies) { $0.objectGroup ?? "Other goals" }
        let groupOrder = grouped.keys.sorted { a, b in
            let ga = grouped[a]?.first?.groupOrder ?? 0
            let gb = grouped[b]?.first?.groupOrder ?? 0
            return ga == gb ? a < b : ga < gb
        }
        var out = ""
        for group in groupOrder {
            let items = (grouped[group] ?? []).sorted { $0.order < $1.order }
            var rows = ""
            for p in items {
                let pct = Int((p.fraction * 100).rounded())
                let color = pct >= 100 ? "#30d158" : "#ffb84d"
                rows += """
                <div class="piggy">
                  <div class="piggy-top">
                    <span class="row-name">\(esc(p.name))</span>
                    <span class="row-amt">\(fmt(p.currentAmount, p.currencyCode)) / \(fmt(p.targetAmount, p.currencyCode))</span>
                  </div>
                  <div class="track"><div class="fill" style="width:\(pct)%;background:\(color)"></div></div>
                </div>
                """
            }
            out += """
            <section class="card">
              <h2>\(esc(group))</h2>
              <div class="list">\(rows)</div>
            </section>
            """
        }
        return out
    }

    private static func transactionsSection(visible: [FFTransaction], conv: CurrencyConverter,
                                            base: String) -> String {
        let recent = visible.prefix(60)
        guard !recent.isEmpty else { return "" }
        var rows = ""
        for t in recent {
            let (v, converted) = conv.value(t)
            let income = t.isIncome
            let amt = (income ? "+" : "−") + fmt(abs(v), base, approx: converted)
            let date = t.date.formatted(.dateTime.day().month(.abbreviated))
            rows += """
            <div class="txn">
              <div class="txn-l">
                <span class="txn-desc">\(esc(t.transactionDescription))</span>
                <span class="txn-cat">\(esc(t.categoryLabel)) · \(esc(date))</span>
              </div>
              <span class="txn-amt \(income ? "in" : "")">\(amt)</span>
            </div>
            """
        }
        return """
        <section class="card">
          <h2>Recent transactions</h2>
          <div class="list">\(rows)</div>
        </section>
        """
    }

    // MARK: Page shell + styles

    private static func shell(title: String, updated: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="dark">
        <title>\(esc(title))</title>
        <style>
        :root{--bg:#0b1220;--card:#151f33;--card2:#1b2742;--ink:#e8edf7;--dim:#93a1bd;
          --amber:#ffb84d;--pos:#34c759;--neg:#ff6b6b;--line:#243152;}
        *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
        body{margin:0;background:var(--bg);color:var(--ink);
          font:16px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
          padding:max(env(safe-area-inset-top),12px) 14px calc(env(safe-area-inset-bottom) + 28px);
          max-width:680px;margin:0 auto;}
        header{display:flex;align-items:baseline;justify-content:space-between;
          padding:6px 2px 16px;}
        header h1{font-size:22px;margin:0;letter-spacing:.3px;}
        header h1 span{color:var(--amber);}
        header .upd{font-size:12px;color:var(--dim);}
        section{margin-bottom:16px;}
        .card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:16px;}
        .card h2{font-size:13px;text-transform:uppercase;letter-spacing:.6px;color:var(--dim);
          margin:0 0 12px;font-weight:600;}
        .empty{padding:60px 20px;text-align:center;color:var(--dim);}
        /* Timeframe + amortise toggles — CSS-only tabs (no JS; work in Quick Look) */
        .tabin{position:absolute;width:0;height:0;opacity:0;pointer-events:none;}
        .panel{display:none;}
        .amrow,.ranges{display:flex;gap:6px;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none;}
        .amrow::-webkit-scrollbar,.ranges::-webkit-scrollbar{display:none;}
        .amrow{padding:2px 2px 8px;}
        .ranges{padding:2px 2px 14px;}
        .amrow label,.ranges label{flex:0 0 auto;border:1px solid var(--line);background:var(--card);
          color:var(--ink);font-size:13px;font-weight:600;padding:8px 14px;border-radius:999px;
          cursor:pointer;user-select:none;}
        /* Hero */
        .hero{display:flex;gap:16px;justify-content:space-between;border-radius:20px;padding:22px;
          background:linear-gradient(135deg,#0d735c,#063a44);}
        .hero.neg{background:linear-gradient(135deg,#8c2626,#4d0d26);}
        .hero-period{font-size:13px;color:rgba(255,255,255,.7);margin-bottom:2px;}
        .hero-head{font-size:15px;font-weight:600;color:rgba(255,255,255,.85);}
        .hero-big{font-size:46px;font-weight:800;letter-spacing:-1px;margin:2px 0 12px;}
        .pills{display:flex;gap:10px;flex-wrap:wrap;}
        .pill{background:rgba(255,255,255,.13);border-radius:999px;padding:6px 12px;font-size:13px;
          display:flex;flex-direction:column;}
        .pill span{font-size:11px;color:rgba(255,255,255,.7);}
        .pill b{font-weight:700;}
        .commit{margin-top:10px;display:flex;flex-direction:column;gap:3px;}
        .commit-row{display:flex;justify-content:space-between;gap:10px;font-size:12px;
          color:rgba(255,255,255,.75);}
        .commit-row b{font-weight:700;color:#fff;}
        .hero-aside{display:flex;flex-direction:column;align-items:flex-end;gap:6px;text-align:right;
          min-width:120px;}
        .hero-aside-row .lbl{display:block;font-size:12px;color:rgba(255,255,255,.7);}
        .hero-aside-row .val{font-size:22px;font-weight:800;}
        .hero-aside-row.sub{font-size:11px;color:rgba(255,255,255,.7);}
        .ring{--pct:0;width:84px;height:84px;border-radius:50%;
          background:conic-gradient(var(--amber) calc(var(--pct)*1%),rgba(255,255,255,.16) 0);
          display:flex;align-items:center;justify-content:center;}
        .ring-inner{width:64px;height:64px;border-radius:50%;background:rgba(0,0,0,.25);
          display:flex;flex-direction:column;align-items:center;justify-content:center;font-size:22px;}
        .ring-inner span{font-size:12px;font-weight:700;}
        /* Donut */
        .donut-wrap{display:flex;gap:18px;align-items:center;flex-wrap:wrap;}
        .donut{width:150px;height:150px;border-radius:50%;position:relative;flex:0 0 auto;margin:0 auto;}
        .donut-hole{position:absolute;inset:26px;border-radius:50%;background:var(--card);
          display:flex;flex-direction:column;align-items:center;justify-content:center;}
        .donut-cap{font-size:11px;color:var(--dim);text-transform:uppercase;letter-spacing:.5px;}
        .donut-hole b{font-size:18px;}
        .legend{flex:1 1 220px;min-width:200px;}
        .leg-row{display:flex;align-items:center;gap:8px;padding:4px 0;font-size:14px;
          border-bottom:1px solid var(--line);}
        .leg-row:last-child{border-bottom:none;}
        .dot{width:10px;height:10px;border-radius:3px;flex:0 0 auto;}
        .leg-name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
        .leg-amt{font-variant-numeric:tabular-nums;}
        .leg-pct{color:var(--dim);font-size:12px;width:38px;text-align:right;}
        /* Trend chart with Y-axis */
        .trend-chart{display:flex;gap:8px;}
        .yaxis{display:flex;flex-direction:column;justify-content:space-between;height:120px;
          font-size:10px;color:var(--dim);text-align:right;font-variant-numeric:tabular-nums;}
        .plot{flex:1;min-width:0;}
        .bars{position:relative;display:flex;align-items:flex-end;gap:4px;height:120px;
          border-bottom:1px solid var(--line);
          background-image:linear-gradient(var(--line),var(--line)),linear-gradient(var(--line),var(--line));
          background-size:100% 1px,100% 1px;background-position:0 0,0 50%;background-repeat:no-repeat;}
        .bar-col{flex:1;display:flex;align-items:flex-end;justify-content:center;height:100%;}
        .bar{width:100%;max-width:22px;border-radius:5px 5px 0 0;background:#2aa6b8;position:relative;z-index:1;}
        .bar.hot{background:var(--amber);}
        .avgline{position:absolute;left:0;right:0;height:0;border-top:1px dashed rgba(255,255,255,.45);z-index:2;}
        .xlabels{display:flex;gap:4px;margin-top:4px;}
        .xlabels span{flex:1;text-align:center;font-size:10px;color:var(--dim);}
        .bars-foot{margin-top:8px;font-size:12px;color:var(--dim);text-align:right;}
        /* Averages table */
        .avg-sub{font-size:12px;color:var(--dim);margin:-6px 0 10px;}
        .avg-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch;}
        .avg{width:100%;border-collapse:collapse;font-size:13px;}
        .avg th{font-size:10px;text-transform:uppercase;letter-spacing:.4px;color:var(--dim);
          font-weight:600;text-align:right;padding:0 6px 6px;white-space:nowrap;}
        .avg th:first-child{text-align:left;}
        .avg td{padding:8px 6px;border-top:1px solid var(--line);text-align:right;
          font-variant-numeric:tabular-nums;white-space:nowrap;}
        .avg-cat{text-align:left!important;display:flex;align-items:center;gap:8px;}
        .d-up{color:var(--neg);font-weight:600;}
        .d-down{color:var(--pos);font-weight:600;}
        .d-flat{color:var(--dim);}
        .avg-empty{color:var(--dim);font-size:14px;padding:8px 0;}
        /* Lists */
        .list{display:flex;flex-direction:column;}
        .row-amt{font-variant-numeric:tabular-nums;color:var(--dim);}
        .piggy{padding:9px 0;border-bottom:1px solid var(--line);}
        .piggy:last-child{border-bottom:none;}
        .piggy-top{display:flex;justify-content:space-between;gap:10px;font-size:14px;margin-bottom:6px;}
        .track{height:8px;border-radius:5px;background:rgba(255,255,255,.08);overflow:hidden;}
        .fill{height:100%;border-radius:5px;}
        .txn{display:flex;justify-content:space-between;gap:10px;padding:8px 0;
          border-bottom:1px solid var(--line);}
        .txn:last-child{border-bottom:none;}
        .txn-l{display:flex;flex-direction:column;min-width:0;}
        .txn-desc{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
        .txn-cat{font-size:12px;color:var(--dim);}
        .txn-amt{font-variant-numeric:tabular-nums;font-weight:600;white-space:nowrap;}
        .txn-amt.in{color:var(--pos);}
        </style>
        </head>
        <body>
        <header><h1>Firefly<span>Dash</span></h1><span class="upd">Updated \(esc(updated))</span></header>
        \(body)
        </body>
        </html>
        """
    }
}
