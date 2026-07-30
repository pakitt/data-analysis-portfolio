import Foundation
import LocalAuthentication
import Security

/// Gatekeeper for the Firefly III access token.
///
/// The token is stored as a synchronizable internet password, so it appears
/// in Apple's Passwords app (under the server's host name) and follows the
/// user's iCloud Keychain to their other Macs. Touch ID is an app-level gate:
/// the app authenticates the user once per launch before reading the token,
/// then caches it in memory so Settings and the sync engine never re-prompt.
@MainActor
final class TokenStore {
    static let shared = TokenStore()
    private var cached: String?
    /// Single-flight: concurrent callers (e.g. the eagerly built Settings
    /// scene plus a sync) await the same authentication instead of each
    /// presenting their own prompt.
    private var inFlight: Task<String?, Never>?

    /// Returns the token, prompting Touch ID at most once per launch.
    /// nil = authentication failed/cancelled or no token stored yet.
    func load() async -> String? {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }
        let task = Task { await authenticateAndLoad() }
        inFlight = task
        let token = await task.value
        inFlight = nil
        return token
    }

    private func authenticateAndLoad() async -> String? {
        let context = LAContext()
        do {
            guard try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "unlock your Firefly III access token") else { return nil }
        } catch {
            return nil
        }

        if let token = Keychain.load() {
            cached = token
            return token
        }
        // One-time migration from the older storage generations (the Touch
        // ID-guarded item needs the just-evaluated context to read). Only
        // delete the old copies once the new item verifiably reads back.
        if let old = Keychain.protectedLoad(context: context) ?? Keychain.legacyLoad() {
            if save(old) == nil {
                Keychain.protectedDelete()
                Keychain.legacyDelete()
            }
            cached = old
            return old
        }
        return nil
    }

    /// Where the last successful save landed, for the Settings caption.
    private(set) var lastStore: Keychain.Store?

    /// Stores a new token (typed in Settings) and updates the cache.
    /// Returns nil on success, otherwise a message describing the failure —
    /// earlier versions dropped the token silently when the keychain refused
    /// the write, which looked like "the app forgot my key".
    @discardableResult
    func save(_ token: String) -> String? {
        let server = UserDefaults.standard.string(forKey: "serverURL")
            .flatMap(URL.init(string:))?.host() ?? "firefly.local"
        let (status, store) = Keychain.save(value: token, server: server)
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Couldn't save the token to the keychain: \(detail)"
        }
        guard Keychain.load() == token else {
            return "The token didn't persist in the keychain. Check that the app is properly signed."
        }
        cached = token
        lastStore = store
        return nil
    }
}
