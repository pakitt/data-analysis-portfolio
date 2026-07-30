import Foundation

// MARK: - API DTOs (Firefly III v1 JSON:API shapes)

struct FFPage<T: Decodable>: Decodable {
    let data: [T]
    let meta: FFMeta?
}

struct FFMeta: Decodable {
    let pagination: FFPagination?
}

struct FFPagination: Decodable {
    let total: Int
    let count: Int
    let current_page: Int
    let total_pages: Int
}

struct FFTransactionGroupDTO: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let transactions: [FFSplitDTO]
    }
}

struct FFSplitDTO: Decodable {
    let transaction_journal_id: String
    let date: String
    let amount: String
    let currency_code: String?
    let description: String
    let type: String
    let category_name: String?
    let budget_name: String?
    let source_name: String?
    let destination_name: String?
    let tags: [String]?
    let notes: String?
    let foreign_amount: String?
    let foreign_currency_code: String?
}

struct FFAccountDTO: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let type: String
        let current_balance: String?
        let currency_code: String?
    }
}

struct FFPiggyBankDTO: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let current_amount: String?
        let target_amount: String?
        let currency_code: String?
        let object_group_title: String?
        let object_group_order: Int?
        let order: Int?
        let save_per_month: String?
        let start_date: String?
        let target_date: String?
        /// Older Firefly: a single attached account id (number or string).
        let account_id: FlexID?
        let account_name: String?
        /// Newer Firefly (v6.1+): a piggy links to one or more accounts.
        let accounts: [PiggyAccount]?
    }

    struct PiggyAccount: Decodable {
        /// Firefly names this `account_id` (not `id`) in the read response.
        let account_id: FlexID?
        let name: String?
    }
}

/// Decodes an identifier that the API may emit as either a JSON number or string.
struct FlexID: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else if let s = try? c.decode(String.self) { value = s }
        else { value = nil }
    }
}

enum FireflyAPIError: LocalizedError {
    case badURL
    case http(Int, String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server URL is invalid."
        case .http(let code, let body): return "Server returned HTTP \(code): \(body.prefix(200))"
        case .noToken: return "No access token configured. Open Settings and paste a Personal Access Token."
        }
    }
}

// MARK: - Client

/// Thin async client for the Firefly III REST API.
/// Optionally trusts self-signed certificates for the configured host only.
final class FireflyAPI: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let baseURL: URL
    private let token: String
    private let trustSelfSigned: Bool
    private lazy var session: URLSession = {
        URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }()

    init(baseURLString: String, token: String, trustSelfSigned: Bool) throws {
        guard let url = URL(string: baseURLString) else { throw FireflyAPIError.badURL }
        guard !token.isEmpty else { throw FireflyAPIError.noToken }
        self.baseURL = url
        self.token = token
        self.trustSelfSigned = trustSelfSigned
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        let http = resp as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw FireflyAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Fetch all transaction groups between two dates, walking pagination.
    func transactions(start: Date, end: Date,
                      progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [FFTransactionGroupDTO] {
        // "yyyy-MM-dd" in local time, as the Firefly API expects.
        let fmt = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)
        var all: [FFTransactionGroupDTO] = []
        var page = 1
        var totalPages = 1
        repeat {
            let result: FFPage<FFTransactionGroupDTO> = try await get("/api/v1/transactions", query: [
                .init(name: "start", value: start.formatted(fmt)),
                .init(name: "end", value: end.formatted(fmt)),
                .init(name: "limit", value: "200"),
                .init(name: "page", value: String(page)),
            ])
            all.append(contentsOf: result.data)
            totalPages = result.meta?.pagination?.total_pages ?? 1
            progress?(page, totalPages)
            page += 1
        } while page <= totalPages
        return all
    }

    func accounts() async throws -> [FFAccountDTO] {
        var all: [FFAccountDTO] = []
        var page = 1
        var totalPages = 1
        repeat {
            let result: FFPage<FFAccountDTO> = try await get("/api/v1/accounts", query: [
                .init(name: "limit", value: "100"),
                .init(name: "page", value: String(page)),
            ])
            all.append(contentsOf: result.data)
            totalPages = result.meta?.pagination?.total_pages ?? 1
            page += 1
        } while page <= totalPages
        return all
    }

    func piggyBanks() async throws -> [FFPiggyBankDTO] {
        var all: [FFPiggyBankDTO] = []
        var page = 1
        var totalPages = 1
        repeat {
            let result: FFPage<FFPiggyBankDTO> = try await get("/api/v1/piggy-banks", query: [
                .init(name: "limit", value: "100"),
                .init(name: "page", value: String(page)),
            ])
            all.append(contentsOf: result.data)
            totalPages = result.meta?.pagination?.total_pages ?? 1
            page += 1
        } while page <= totalPages
        return all
    }

    /// The date of the newest transaction on the server (the list is ordered
    /// newest-first), for a cheap "is my local copy behind?" check. nil when
    /// the server has no transactions.
    func newestTransactionDate() async throws -> Date? {
        let result: FFPage<FFTransactionGroupDTO> = try await get("/api/v1/transactions", query: [
            .init(name: "limit", value: "1"),
            .init(name: "page", value: "1"),
        ])
        let iso = Date.ISO8601FormatStyle(timeZoneSeparator: .colon)
        let isoFractional = Date.ISO8601FormatStyle(timeZoneSeparator: .colon,
                                                    includingFractionalSeconds: true)
        return result.data
            .flatMap { $0.attributes.transactions.map(\.date) }
            .compactMap { s in
                (try? iso.parse(s)) ?? (try? isoFractional.parse(s)) ?? (try? Date(s, strategy: .iso8601))
            }
            .max()
    }

    /// Quick connectivity check.
    func about() async throws {
        struct About: Decodable { let data: Inner; struct Inner: Decodable { let version: String } }
        let _: About = try await get("/api/v1/about", query: [])
    }

    // MARK: URLSessionDelegate — opt-in trust for self-signed certs on the configured host

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard trustSelfSigned,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == baseURL.host,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
