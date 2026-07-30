import Foundation
import SwiftData
import SwiftUI
import LocalAuthentication

/// Orchestrates pulling data from Firefly into SwiftData.
/// First run: full history (back to `historyYears`). Refresh: last `refreshDays`, upserted.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case syncing(String)
        case failed(String)
    }

    var status: Status = .idle
    var lastRefresh: Date?
    /// True when the server has a transaction newer than our local copy — a hint
    /// that a refresh is worthwhile. Set by `checkForUpdates`, cleared on sync.
    var serverHasNewer = false

    static let historyYears = 10
    /// A normal refresh re-fetches (and upserts) this many days back, so edits
    /// to fairly recent transactions in Firefly show up without a full re-sync.
    static let refreshDays = 366

    func refresh(context: ModelContext) async {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let trustSelfSigned = UserDefaults.standard.bool(forKey: "trustSelfSigned")
        // All the CPU-heavy parsing/upserting below runs on this background
        // actor (its own ModelContext, same store) instead of here on
        // @MainActor — see SyncActor's doc comment for why that matters.
        let sync = SyncActor(modelContainer: context.container)
        if lastRefresh == nil { lastRefresh = await sync.restoreLastRefresh() }
        let token = await TokenStore.shared.load() ?? ""

        do {
            let api = try FireflyAPI(baseURLString: serverURL, token: token, trustSelfSigned: trustSelfSigned)
            // The Firefly container may still be warming up (or briefly busy) on
            // first launch, so retry the connectivity check a few times with
            // backoff before reporting a failure.
            status = .syncing("Connecting…")
            for attempt in 1...5 {
                do {
                    try await api.about()
                    break
                } catch {
                    guard attempt < 5 else { throw error }
                    status = .syncing("Connecting… (retry \(attempt))")
                    try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }

            let isFirstRun = try await sync.isFirstRun()
            let end = Date()
            let start: Date = isFirstRun
                ? Calendar.current.date(byAdding: .year, value: -Self.historyYears, to: end)!
                : Calendar.current.date(byAdding: .day, value: -Self.refreshDays, to: end)!

            status = .syncing(isFirstRun ? "First sync — fetching full history…" : "Fetching recent transactions…")
            let groups = try await api.transactions(start: start, end: end) { page, total in
                Task { @MainActor [weak self] in
                    self?.status = .syncing("Fetching transactions… page \(page)/\(total)")
                }
            }
            try await sync.upsert(groups: groups)

            status = .syncing("Fetching accounts…")
            let accounts = try await api.accounts()
            try await sync.upsert(accounts: accounts)

            status = .syncing("Fetching piggy banks…")
            let piggies = try await api.piggyBanks()
            try await sync.upsert(piggies: piggies)

            lastRefresh = try await sync.markSynced(isFirstRun: isFirstRun)
            serverHasNewer = false

            // Refresh the iPhone snapshot, when enabled and a folder is set.
            // Real data only — demo mode must never clobber the phone's file.
            if !UserDefaults.standard.bool(forKey: "useSampleData") {
                await sync.exportWebSnapshotIfNeeded()
            }
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Cheap, best-effort poll: is there a transaction on the server newer than
    /// our local copy? Sets `serverHasNewer`. Detects new transactions (the
    /// common case from auto-import); edits/deletions of existing rows aren't
    /// visible this way. Errors are swallowed — this never disturbs the UI.
    /// Loads the persisted last-sync time into memory (it's saved in SyncState
    /// but the engine starts fresh each launch), so the footer shows the real
    /// time rather than "not synced yet".
    func restoreLastRefresh(context: ModelContext) async {
        if lastRefresh == nil {
            lastRefresh = await SyncActor(modelContainer: context.container).restoreLastRefresh()
        }
    }

    func checkForUpdates(context: ModelContext) async {
        if case .syncing = status { return }
        await restoreLastRefresh(context: context)
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let trustSelfSigned = UserDefaults.standard.bool(forKey: "trustSelfSigned")
        let token = await TokenStore.shared.load() ?? ""
        guard !serverURL.isEmpty, !token.isEmpty,
              let api = try? FireflyAPI(baseURLString: serverURL, token: token,
                                        trustSelfSigned: trustSelfSigned),
              let serverNewest = try? await api.newestTransactionDate() else { return }

        let localNewest = try? await SyncActor(modelContainer: context.container).newestLocalTransactionDate()
        // Only flag when we already have data; an empty store just shows "not synced".
        serverHasNewer = (localNewest ?? nil).map { serverNewest > $0 } ?? false
    }
}

// MARK: - Keychain helper for the API token (access it through TokenStore)

enum Keychain {
    /// Where a token ended up.
    enum Store { case cloud, local }

    private static let account = "firefly-iii-token"
    private static let legacyService = "com.paolo.FireflyDash"

    /// iCloud-synchronizable item in the data-protection keychain — shows in
    /// Apple's Passwords app. Needs a keychain-access-groups entitlement
    /// (i.e. a provisioning profile), which this app only has when Xcode
    /// signs it that way.
    private static func cloudQuery() -> [String: Any] {
        [kSecClass as String: kSecClassInternetPassword,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
         kSecUseDataProtectionKeychain as String: true]
    }

    /// Plain login-keychain item — always available to a sandboxed app, on
    /// any Mac, regardless of provisioning. Visible in Keychain Access.
    private static func localQuery() -> [String: Any] {
        [kSecClass as String: kSecClassInternetPassword,
         kSecAttrAccount as String: account]
    }

    private static func commonAttributes(value: String, server: String) -> [String: Any] {
        [kSecAttrServer as String: server,
         kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
         kSecAttrLabel as String: "Firefly III — FireflyDash",
         kSecAttrDescription as String: "Personal Access Token",
         kSecValueData as String: Data(value.utf8)]
    }

    /// Saves the token, preferring the iCloud/Passwords-app item and falling
    /// back to the local login keychain when the OS refuses for lack of
    /// entitlements. Returns the final status and where the token landed.
    static func save(value: String, server: String) -> (status: OSStatus, store: Store) {
        SecItemDelete(cloudQuery() as CFDictionary)
        SecItemDelete(localQuery() as CFDictionary)

        var cloud = cloudQuery()
        cloud[kSecAttrSynchronizable as String] = true
        cloud[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        cloud.merge(commonAttributes(value: value, server: server)) { _, new in new }
        var status = SecItemAdd(cloud as CFDictionary, nil)
        if status == errSecSuccess { return (status, .cloud) }

        guard status == errSecMissingEntitlement else { return (status, .cloud) }
        var local = localQuery()
        local.merge(commonAttributes(value: value, server: server)) { _, new in new }
        status = SecItemAdd(local as CFDictionary, nil)
        return (status, .local)
    }

    static func load() -> String? {
        for query in [cloudQuery(), localQuery()] {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let token = String(data: data, encoding: .utf8) {
                return token
            }
        }
        return nil
    }

    // Earlier storage generations, kept only so existing tokens migrate once:
    // a Touch ID-guarded generic password, and before that a plain login-
    // keychain item.

    private static func protectedQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: "fireflyToken",
         kSecAttrService as String: legacyService,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func protectedLoad(context: LAContext) -> String? {
        var q = protectedQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = context
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func protectedDelete() {
        SecItemDelete(protectedQuery() as CFDictionary)
    }

    static func legacyLoad() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "fireflyToken",
            kSecAttrService as String: legacyService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func legacyDelete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "fireflyToken",
            kSecAttrService as String: legacyService,
        ]
        SecItemDelete(q as CFDictionary)
    }
}
