import SwiftUI
import SwiftData

@main
struct FireflyDashApp: App {
    @State private var sync = SyncEngine()
    /// When on, the app reads from a separate demo store instead of the real
    /// (Firefly-synced) one — for showcasing without exposing real finances.
    @AppStorage("useSampleData") private var useSampleData = false
    @State private var container: ModelContainer

    static let schema = Schema([FFTransaction.self, FFAccount.self, FFPiggyBank.self,
                                FFBudgetLimit.self, SyncState.self])

    init() {
        // This build ships as a portfolio/demo artifact: default to the
        // built-in sample dataset so it's showcase-ready with no Firefly III
        // server needed. A real value written later (toggling the Settings
        // switch) still overrides this.
        UserDefaults.standard.register(defaults: ["useSampleData": true])
        let sample = UserDefaults.standard.bool(forKey: "useSampleData")
        let c = Self.makeContainer(sample: sample)
        // App init runs on the main thread; assumeIsolated lets us touch the
        // main-actor mainContext to seed the demo store before first render.
        if sample { MainActor.assumeIsolated { SampleData.populateIfNeeded(c) } }
        _container = State(initialValue: c)
    }

    /// Build a container backed by either the real store (`default.store`) or the
    /// demo store (`sample.store`). The store is just a local cache, so if a
    /// migration can't be applied in place we wipe that store and rebuild rather
    /// than crashing.
    static func makeContainer(sample: Bool) -> ModelContainer {
        let storeName = sample ? "sample.store" : "default.store"
        let config: ModelConfiguration = sample
            ? ModelConfiguration(schema: schema,
                                 url: URL.applicationSupportDirectory.appending(path: storeName))
            : ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let appSupport = URL.applicationSupportDirectory
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: appSupport.appending(path: "\(storeName)\(suffix)"))
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sync)
                // Swap the backing store when the sample toggle changes; seed the
                // demo store the first time it's switched on.
                .onChange(of: useSampleData) { _, sample in
                    let c = Self.makeContainer(sample: sample)
                    if sample { SampleData.populateIfNeeded(c) }
                    container = c
                }
        }
        .modelContainer(container)

        MenuBarExtra {
            MenuBarView()
                .environment(sync)
                .modelContainer(container)
        } label: {
            Image(systemName: "flame.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(sync)
                .modelContainer(container)
        }
    }
}
