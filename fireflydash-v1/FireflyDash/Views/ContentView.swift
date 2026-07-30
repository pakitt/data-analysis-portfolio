import SwiftUI
import SwiftData

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transactions = "Transactions"
    case categories = "Categories"
    case budgets = "Budgets"
    case piggyBanks = "Piggy banks"
    case averages = "Averages"
    case tags = "Tags"
    case accounts = "Accounts"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .transactions: "list.bullet.rectangle.portrait"
        case .categories: "chart.pie.fill"
        case .budgets: "chart.bar.doc.horizontal"
        case .piggyBanks: "banknote.fill"
        case .averages: "chart.bar.xaxis"
        case .tags: "tag.fill"
        case .accounts: "building.columns.fill"
        }
    }
}

struct ContentView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedSection") private var selectedRaw = Section.dashboard.rawValue
    /// User's sidebar order (comma-separated raw values); Dashboard is always
    /// pinned first regardless of what's stored.
    @AppStorage("sectionOrder") private var sectionOrderRaw = ""
    /// Showcase mode reads from the demo store; never sync against Firefly then.
    @AppStorage("useSampleData") private var useSampleData = false

    private var selection: Binding<Section?> {
        Binding(
            get: { Section(rawValue: selectedRaw) ?? .dashboard },
            set: { selectedRaw = ($0 ?? .dashboard).rawValue }
        )
    }

    @ViewBuilder
    private func sectionView(_ section: Section) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .transactions: TransactionsView()
        case .categories: CategoriesView()
        case .budgets: BudgetsView()
        case .piggyBanks: PiggyBanksView()
        case .averages: AveragesView()
        case .tags: TagsView()
        case .accounts: AccountsView()
        }
    }

    /// Saved order, with any new sections appended and Dashboard forced to the top.
    private var orderedSections: [Section] {
        var result = sectionOrderRaw.split(separator: ",").compactMap { Section(rawValue: String($0)) }
        for s in Section.allCases where !result.contains(s) { result.append(s) }
        result.removeAll { $0 == .dashboard }
        result.insert(.dashboard, at: 0)
        return result
    }

    private func move(from source: IndexSet, to destination: Int) {
        var arr = orderedSections
        arr.move(fromOffsets: source, toOffset: destination)
        arr.removeAll { $0 == .dashboard }
        arr.insert(.dashboard, at: 0)
        sectionOrderRaw = arr.map(\.rawValue).joined(separator: ",")
    }

    var body: some View {
        // Reading the window's own width lets text grow on a big, high-res
        // monitor instead of staying pinned at the same physical size
        // regardless of how much room there is. macOS has no OS-level
        // Dynamic Type support (confirmed in Apple's own HIG), so
        // `\.dynamicTypeSize` — SwiftUI's usual text-scaling hook — silently
        // does nothing here; `.appFont(_:)` (Support/AppFont.swift) reads
        // `\.interfaceScale` instead and constructs real point sizes, so
        // text actually re-lays-out at the target size rather than being
        // stretched as a bitmap (`.scaleEffect`, tried first, worked but
        // came out soft).
        GeometryReader { geo in
            let scale = Self.uiScale(for: geo.size.width)
            NavigationSplitView {
                List(selection: selection) {
                    ForEach(orderedSections) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                            .moveDisabled(section == .dashboard)
                    }
                    .onMove(perform: move)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                .navigationTitle("FireflyDash")
                // Synced-status footer lives at the bottom of the sidebar.
                .safeAreaInset(edge: .bottom) {
                    SyncStatusBar()
                }
            } detail: {
                sectionView(Section(rawValue: selectedRaw) ?? .dashboard)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await sync.refresh(context: context) }
                    } label: {
                        if case .syncing = sync.status {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .keyboardShortcut("r")
                    .disabled(useSampleData)
                    .help(useSampleData ? "Disabled while showing sample data" : "Sync from Firefly III")
                }
            }
            // Auto-sync once on launch (retries handle a still-warming server), and
            // do a lightweight "is there newer data?" check whenever the app
            // returns to the foreground after that.
            .task {
                guard !useSampleData else { return }
                await sync.restoreLastRefresh(context: context)
                await sync.refresh(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !useSampleData {
                    Task { await sync.checkForUpdates(context: context) }
                }
            }
            .environment(\.interfaceScale, scale)
        }
    }

    /// 1.0 (today's size, unchanged) below ~1500pt of window width, growing
    /// linearly to 1.5× by ~2250pt and capped there. Confirmed via a debug
    /// build (temporary on-screen readout + measuring the rendered hero
    /// number against its known point size) that `\.interfaceScale` reaches
    /// content and `.appFont` applies it correctly — the 1.3× cap this used
    /// to have just wasn't a big enough jump to *read* as "scaled" once only
    /// text grows and padding/icons/controls stay fixed (unlike the old
    /// `.scaleEffect` version, which inflated literally everything). Pushed
    /// the ceiling higher rather than also scaling every padding/icon, to
    /// keep this a small, contained change.
    private static func uiScale(for width: CGFloat) -> CGFloat {
        min(1.5, max(1.0, width / 1500))
    }
}

/// Footer at the bottom of the sidebar: shows sync progress/errors, when the
/// data was last synced, and — when a poll has found newer data on the server —
/// an amber "new data" prompt. Click it to refresh.
struct SyncStatusBar: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @AppStorage("useSampleData") private var useSampleData = false

    var body: some View {
        Button {
            if !useSampleData { Task { await sync.refresh(context: context) } }
        } label: {
            content
                .appFont(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No custom background here on purpose: macOS 26's NavigationSplitView
        // sidebar is automatically a floating Liquid Glass surface, and an
        // opaque `.bar` material underneath this footer would both block that
        // and (per Apple's own guidance) risk "glass on glass" artifacting if
        // replaced with another glassEffect layered on top of it instead.
        // Letting the sidebar's own glass show straight through is the
        // correct fix, not adding a second glass surface.
    }

    @ViewBuilder
    private var content: some View {
        if useSampleData {
            Label("Showcase sample data", systemImage: "wand.and.stars")
                .foregroundStyle(.blue)
        } else {
            switch sync.status {
            case .syncing(let message):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(message).lineLimit(2)
                }
                .foregroundStyle(.secondary)
            case .failed(let error):
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            case .idle:
                if sync.serverHasNewer {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("New data on server — refresh").fontWeight(.medium)
                            if let date = sync.lastRefresh {
                                Text("Synced \(date.formatted(.relative(presentation: .named)))")
                                    .appFont(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    }
                    .foregroundStyle(.orange)
                } else if let date = sync.lastRefresh {
                    Label("Synced \(date.formatted(.relative(presentation: .named)))",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Not synced yet", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
