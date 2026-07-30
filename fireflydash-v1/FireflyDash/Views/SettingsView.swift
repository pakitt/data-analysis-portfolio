import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Query private var allTransactions: [FFTransaction]
    @Query(sort: \FFAccount.name) private var accounts: [FFAccount]
    @Query private var piggyBanks: [FFPiggyBank]
    @AppStorage("serverURL") private var serverURL = "https://firefly.local:9799"
    @AppStorage("trustSelfSigned") private var trustSelfSigned = true
    @AppStorage("subThresholdPercent") private var subThresholdPercent = 2.0
    @AppStorage("useSampleData") private var useSampleData = false

    // Dataset-scoped settings keep a real copy and a "sample." copy; the active
    // one is chosen by useSampleData so demo and real choices never mix.
    @AppStorage("baseCurrency") private var baseCurrencyReal = ""
    @AppStorage("sample.baseCurrency") private var baseCurrencySample = ""
    @AppStorage("savingsAccountIDs") private var savingsRealRaw = ""
    @AppStorage("sample.savingsAccountIDs") private var savingsSampleRaw = ""
    @AppStorage("fundingAccountIDs") private var fundingRealRaw = ""
    @AppStorage("sample.fundingAccountIDs") private var fundingSampleRaw = ""
    @AppStorage("excludedCategories") private var excludedRealRaw = ""
    @AppStorage("sample.excludedCategories") private var excludedSampleRaw = ""
    @AppStorage("essentialTag") private var essentialTagReal = ""
    @AppStorage("sample.essentialTag") private var essentialTagSample = ""
    @AppStorage("paycheckKeyword") private var paycheckKeywordReal = ""
    @AppStorage("sample.paycheckKeyword") private var paycheckKeywordSample = ""
    @AppStorage("paycheckStartTS") private var paycheckStartRealTS = 0.0
    @AppStorage("sample.paycheckStartTS") private var paycheckStartSampleTS = 0.0
    @AppStorage("externalMonthlySavings") private var externalSavingsReal = 0.0
    @AppStorage("sample.externalMonthlySavings") private var externalSavingsSample = 0.0
    @AppStorage("essentialPiggyGroups") private var essentialPiggyGroupsRealRaw = ""
    @AppStorage("sample.essentialPiggyGroups") private var essentialPiggyGroupsSampleRaw = ""

    private var savingsAccountIDsRaw: String {
        get { useSampleData ? savingsSampleRaw : savingsRealRaw }
        nonmutating set { if useSampleData { savingsSampleRaw = newValue } else { savingsRealRaw = newValue } }
    }
    private var fundingAccountIDsRaw: String {
        get { useSampleData ? fundingSampleRaw : fundingRealRaw }
        nonmutating set { if useSampleData { fundingSampleRaw = newValue } else { fundingRealRaw = newValue } }
    }
    private var excludedRaw: String {
        get { useSampleData ? excludedSampleRaw : excludedRealRaw }
        nonmutating set { if useSampleData { excludedSampleRaw = newValue } else { excludedRealRaw = newValue } }
    }
    private var paycheckStartTS: Double {
        get { useSampleData ? paycheckStartSampleTS : paycheckStartRealTS }
        nonmutating set { if useSampleData { paycheckStartSampleTS = newValue } else { paycheckStartRealTS = newValue } }
    }
    private var baseCurrency: Binding<String> {
        Binding(get: { useSampleData ? baseCurrencySample : baseCurrencyReal },
                set: { if useSampleData { baseCurrencySample = $0 } else { baseCurrencyReal = $0 } })
    }
    private var paycheckKeyword: Binding<String> {
        Binding(get: { useSampleData ? paycheckKeywordSample : paycheckKeywordReal },
                set: { if useSampleData { paycheckKeywordSample = $0 } else { paycheckKeywordReal = $0 } })
    }
    private var essentialTag: Binding<String> {
        Binding(get: { useSampleData ? essentialTagSample : essentialTagReal },
                set: { if useSampleData { essentialTagSample = $0 } else { essentialTagReal = $0 } })
    }
    private var externalMonthlySavings: Binding<Double> {
        Binding(get: { useSampleData ? externalSavingsSample : externalSavingsReal },
                set: { if useSampleData { externalSavingsSample = $0 } else { externalSavingsReal = $0 } })
    }
    private var essentialPiggyGroupsRaw: String {
        get { useSampleData ? essentialPiggyGroupsSampleRaw : essentialPiggyGroupsRealRaw }
        nonmutating set { if useSampleData { essentialPiggyGroupsSampleRaw = newValue } else { essentialPiggyGroupsRealRaw = newValue } }
    }
    private var essentialPiggyGroups: Set<String> {
        Set(essentialPiggyGroupsRaw.split(separator: "\n").map(String.init))
    }
    private func toggleEssentialPiggyGroup(_ group: String) {
        var set = essentialPiggyGroups
        if set.contains(group) { set.remove(group) } else { set.insert(group) }
        essentialPiggyGroupsRaw = set.sorted().joined(separator: "\n")
    }
    /// Every object group Firefly reports across the synced piggy banks —
    /// Budgets can only ever show groups that actually exist.
    private var piggyGroups: [String] {
        Set(piggyBanks.map { $0.objectGroup ?? "Ungrouped" }).sorted()
    }
    @AppStorage(WebExport.autoExportKey) private var exportAfterSync = false
    @State private var token = ""
    @State private var testResult: String?
    @State private var tokenStatus: (message: String, isError: Bool)?
    @State private var exportFolder: String? = WebExport.chosenFolderPath
    @State private var exportStatus: (message: String, isError: Bool)?

    private var allCategories: [String] {
        Set(allTransactions.map { $0.categoryName ?? "Uncategorised" }).sorted()
    }

    /// Every currency seen in the imported data.
    private var detectedCurrencies: [String] {
        var codes = Set(allTransactions.map(\.currencyCode))
        codes.formUnion(allTransactions.compactMap(\.foreignCurrencyCode))
        codes.formUnion(accounts.map(\.currencyCode))
        return codes.sorted()
    }

    private var assetAccounts: [FFAccount] { accounts.filter { $0.type == "asset" } }

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    private var savingsIDs: Set<String> {
        Set(savingsAccountIDsRaw.split(separator: "\n").map(String.init))
    }

    private func toggleSavings(_ accountID: String) {
        var set = savingsIDs
        if set.contains(accountID) { set.remove(accountID) } else { set.insert(accountID) }
        savingsAccountIDsRaw = set.sorted().joined(separator: "\n")
    }

    private var fundingIDs: Set<String> {
        Set(fundingAccountIDsRaw.split(separator: "\n").map(String.init))
    }

    private func toggleFunding(_ accountID: String) {
        var set = fundingIDs
        if set.contains(accountID) { set.remove(accountID) } else { set.insert(accountID) }
        fundingAccountIDsRaw = set.sorted().joined(separator: "\n")
    }

    /// DatePicker bridge for the paycheck regular-start date, which is stored
    /// as a `timeIntervalSinceReferenceDate` (0 = use the default).
    private var paycheckStart: Binding<Date> {
        Binding(
            get: { paycheckStartTS == 0 ? Insights.defaultPaycheckStart
                                        : Date(timeIntervalSinceReferenceDate: paycheckStartTS) },
            set: { paycheckStartTS = $0.timeIntervalSinceReferenceDate })
    }

    private var excluded: Set<String> {
        Set(excludedRaw.split(separator: "\n").map(String.init))
    }

    private func toggle(_ category: String) {
        var set = excluded
        if set.contains(category) { set.remove(category) } else { set.insert(category) }
        excludedRaw = set.sorted().joined(separator: "\n")
    }

    // MARK: Excluded categories, as a tree (main category → subcategories)

    private struct CategoryGroup: Identifiable {
        var id: String { main }
        let main: String
        /// Full "Main:Sub" strings for this main's subcategories (empty when
        /// the main category has no subcategories of its own).
        let subs: [String]
    }

    private var categoryTree: [CategoryGroup] {
        let byMain = Dictionary(grouping: allCategories) { Insights.splitCategory($0).main }
        return byMain.keys.sorted().map { main in
            let subs = (byMain[main] ?? []).filter { $0 != main }.sorted()
            return CategoryGroup(main: main, subs: subs)
        }
    }

    private enum TriState { case none, some, all }

    /// A main-only category (no subs) is its own single member; otherwise the
    /// members are its full "Main:Sub" strings.
    private func members(_ group: CategoryGroup) -> [String] {
        group.subs.isEmpty ? [group.main] : group.subs
    }

    private func mainState(_ group: CategoryGroup) -> TriState {
        let mem = members(group)
        let excludedCount = mem.filter { excluded.contains($0) }.count
        if excludedCount == 0 { return .none }
        return excludedCount == mem.count ? .all : .some
    }

    /// One click excludes (or re-includes) every subcategory under a main
    /// category at once — going from "none/some excluded" toggles all of
    /// them off, from "all excluded" toggles them all back on.
    private func toggleMain(_ group: CategoryGroup) {
        var set = excluded
        let mem = members(group)
        if mainState(group) == .all {
            mem.forEach { set.remove($0) }
        } else {
            mem.forEach { set.insert($0) }
        }
        excludedRaw = set.sorted().joined(separator: "\n")
    }

    private func triStateIcon(_ state: TriState) -> String {
        switch state {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }

    private func categoryRow(_ group: CategoryGroup) -> some View {
        let state = mainState(group)
        return HStack {
            Button { toggleMain(group) } label: {
                Image(systemName: triStateIcon(state))
                    .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            Text(group.main)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleMain(group) }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            categoriesTab
                .tabItem { Label("Categories", systemImage: "tag") }
            incomeSavingsTab
                .tabItem { Label("Income & Savings", systemImage: "banknote") }
            exportTab
                .tabItem { Label("iPhone Export", systemImage: "iphone") }
        }
        .frame(width: 540, height: 560)
        .task { token = await TokenStore.shared.load() ?? "" }
    }

    // MARK: Tabs

    private var generalTab: some View {
        Form {
            SwiftUI.Section("Firefly III server") {
                TextField("Server URL", text: $serverURL, prompt: Text("https://firefly.local:9799"))
                    .textContentType(.URL)
                SecureField("Personal Access Token", text: $token)
                    .onChange(of: token) {
                        guard !token.isEmpty else { return }
                        if let error = TokenStore.shared.save(token) {
                            tokenStatus = (message: "⚠️ \(error)", isError: true)
                        } else if TokenStore.shared.lastStore == .cloud {
                            tokenStatus = (message: "✓ Saved — visible in Apple's Passwords app and synced via iCloud Keychain.", isError: false)
                        } else {
                            tokenStatus = (message: "✓ Saved to this Mac's keychain (visible in Keychain Access).", isError: false)
                        }
                    }
                if let tokenStatus {
                    Text(tokenStatus.message)
                        .appFont(.caption)
                        .foregroundStyle(tokenStatus.isError ? .red : .green)
                }
                Toggle("Trust self-signed certificate for this host", isOn: $trustSelfSigned)
                Text("Create a token in Firefly under Options → Profile → OAuth → Personal Access Tokens. The token is stored in your keychain.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                HStack {
                    Button("Test connection") {
                        Task {
                            do {
                                let api = try FireflyAPI(baseURLString: serverURL, token: token,
                                                         trustSelfSigned: trustSelfSigned)
                                try await api.about()
                                testResult = "✅ Connected"
                            } catch {
                                testResult = "❌ \(error.localizedDescription)"
                            }
                        }
                    }
                    if let result = testResult {
                        Text(result).appFont(.caption)
                    }
                }
                Button("Sync now") {
                    Task { await sync.refresh(context: context) }
                }
                Button("Re-sync full history") {
                    Task {
                        if let state = try? context.fetch(FetchDescriptor<SyncState>()).first {
                            state.lastFullSync = nil
                        }
                        await sync.refresh(context: context)
                    }
                }
                .help("Fetches all \(SyncEngine.historyYears) years again — use after editing transactions older than a year, since a normal sync only re-checks roughly the last year.")
            }

            SwiftUI.Section("Showcase / demo") {
                Toggle("Use sample data", isOn: $useSampleData)
                Text("Switches the whole app to ~3 years of realistic, fictional data stored separately from your real cache — for demos and screenshots. Your Firefly data is left untouched and syncing is paused. Turn off to return to your own data.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                if useSampleData {
                    Button("Regenerate sample data") {
                        SampleData.regenerate(into: context)
                    }
                    .help("Wipe and rebuild the demo dataset.")
                }
            }

            SwiftUI.Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(appBuild))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var categoriesTab: some View {
        Form {
            SwiftUI.Section("Currency") {
                Picker("Base currency", selection: baseCurrency) {
                    Text("Auto (most used)").tag("")
                    ForEach(detectedCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                Text("All totals and averages are reported in this currency. Amounts that combine more than one currency are marked with ≈.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Small category threshold") {
                HStack {
                    Slider(value: $subThresholdPercent, in: 0...10, step: 0.5) {
                        Text("Threshold")
                    }
                    Text(subThresholdPercent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("Anything smaller than this share of the period's total spending is rolled into \"Other\". Applies to the Cashflow chart's subcategories (max 4 largest per category) and to the donut and pie charts' categories.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Essential vs discretionary") {
                TextField("Essential tag", text: essentialTag, prompt: Text("essential"))
                Text("Transactions tagged with this — set up a Firefly rule to apply it on import, e.g. to rent, insurance, subscriptions — count as essential spending; the Dashboard and Budgets projections treat that as unavoidable before payday. Untagged transactions are discretionary. Leave blank to use \"essential\".")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Excluded categories") {
                Text("Hidden from every view and total (e.g. one-off events like a home purchase). Click a main category to exclude it and all its subcategories at once, or expand it to pick individual subcategories.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                ForEach(categoryTree) { group in
                    if group.subs.isEmpty {
                        categoryRow(group)
                    } else {
                        DisclosureGroup {
                            ForEach(group.subs, id: \.self) { full in
                                Toggle(Insights.splitCategory(full).sub ?? full, isOn: Binding(
                                    get: { excluded.contains(full) },
                                    set: { _ in toggle(full) }))
                                .padding(.leading, 20)
                            }
                        } label: {
                            categoryRow(group)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var incomeSavingsTab: some View {
        Form {
            SwiftUI.Section("Paychecks") {
                TextField("Paycheck category keyword", text: paycheckKeyword,
                          prompt: Text("paycheck"))
                DatePicker("Regular pay started", selection: paycheckStart,
                           displayedComponents: .date)
                Text("Income whose category contains this keyword is treated as a regular paycheck — used for the menu-bar pay-period glance and the Dashboard's savings wording. Income before the start date is ignored when estimating your pay cadence. Leave the keyword blank to use \"paycheck\".")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("External savings (not in Firefly)") {
                HStack {
                    Text("Monthly amount")
                    Spacer()
                    TextField("Amount", value: externalMonthlySavings, format: .number.precision(.fractionLength(0)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
                Text("A flat monthly amount — a pension contribution, an ISA, etc. — you set aside outside Firefly. Subtracted from the Dashboard's savings estimate like a bill.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Savings accounts") {
                Text("Balances of the ticked accounts make up the \"Saved so far\" figure on the Dashboard.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                ForEach(assetAccounts) { account in
                    Toggle("\(account.name) (\(account.currentBalance.currency(account.currencyCode)))",
                           isOn: Binding(
                               get: { savingsIDs.contains(account.accountID) },
                               set: { _ in toggleSavings(account.accountID) }))
                }
            }

            SwiftUI.Section("Funding accounts") {
                Text("Accounts you draw from to top up your piggy banks. Their combined balance shows as \"Available to save\" on the Dashboard.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                ForEach(assetAccounts) { account in
                    Toggle("\(account.name) (\(account.currentBalance.currency(account.currencyCode)))",
                           isOn: Binding(
                               get: { fundingIDs.contains(account.accountID) },
                               set: { _ in toggleFunding(account.accountID) }))
                }
            }

            if !piggyGroups.isEmpty {
                SwiftUI.Section("Essential piggy groups") {
                    Text("Piggy bank groups tick here show up in Budgets as \"what should go into piggy banks this period\" — for goals you fund gradually toward an irregular essential bill (annual insurance, car service) rather than tracking as a recurring Firefly transaction. Firefly has no way to tag a piggy bank's own category, so this is chosen here instead.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(piggyGroups, id: \.self) { group in
                        Toggle(group, isOn: Binding(
                            get: { essentialPiggyGroups.contains(group) },
                            set: { _ in toggleEssentialPiggyGroup(group) }))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var exportTab: some View {
        Form {
            SwiftUI.Section("iPhone export (iCloud)") {
                Text("Writes a self-contained dashboard file (FireflyDash.html) into a folder you choose — put it in iCloud Drive to read it on your iPhone with no app. On the phone, open it from Files, or make a Shortcut (Get File → Quick Look) and add it to your Home Screen. Share the folder via iCloud Drive to give it to a second person.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(exportFolder == nil ? "Choose iCloud folder…" : "Change folder…") {
                        if WebExport.chooseFolder() {
                            exportFolder = WebExport.chosenFolderPath
                            exportStatus = nil
                        }
                    }
                    if let exportFolder {
                        Text(exportFolder)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                if exportFolder != nil {
                    Toggle("Export after each sync", isOn: $exportAfterSync)
                    HStack {
                        Button("Export now") {
                            switch WebExport.export(context: context) {
                            case .success(let url):
                                exportStatus = (message: "✓ Wrote \(url.lastPathComponent)", isError: false)
                            case .failure(let error):
                                exportStatus = (message: "⚠️ \(error.localizedDescription)", isError: true)
                            }
                        }
                        if let last = WebExport.lastExport, exportStatus == nil {
                            Text("Last export: \(last.formatted(date: .abbreviated, time: .shortened))")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let exportStatus {
                        Text(exportStatus.message)
                            .appFont(.caption)
                            .foregroundStyle(exportStatus.isError ? .red : .green)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
