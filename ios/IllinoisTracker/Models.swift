import Foundation
import Security

struct Filing: Codable, Identifiable, Hashable {
    let seq: Int
    let committeeKey: String
    let committeeName: String
    let reportType: String
    let publishedRaw: String?
    let url: String?
    var id: Int { seq }
    var reportURL: URL? {
        guard let url, let result = URL(string: url), result.scheme == "https",
              ["www.elections.il.gov", "elections.il.gov"].contains(result.host ?? "") else { return nil }
        return result
    }
}
struct Committee: Codable, Identifiable, Hashable { let id: String; let name: String }
struct CaucusDirectory: Decodable { let revision: String; let groups: [CaucusGroup] }
struct CaucusGroup: Decodable, Identifiable {
    let id: String
    let name: String
    let pinned: [DirectoryEntry]
    let members: [DirectoryEntry]
}
struct DirectoryEntry: Decodable, Identifiable {
    let id: String
    let member: String
    let lastName: String
    let district: Int?
    let committee: Committee?
    let officialUrl: String?
    let role: String
    var officialURL: URL? {
        guard let officialUrl, let url = URL(string: officialUrl), url.scheme == "https",
              ["elections.il.gov", "www.elections.il.gov"].contains(url.host ?? "") else { return nil }
        return url
    }
}
struct Category: Decodable, Identifiable {
    let id: String; let name: String; let verified: Int; let memberCount: Int
}
struct FilingPage: Decodable { let filings: [Filing]; let hasMore: Bool; let nextCursor: Int?; let history: HistoryStatus? }
struct CommitteePage: Decodable { let committees: [Committee]; let hasMore: Bool; let nextCursor: String? }
struct CategoryPage: Decodable { let categories: [Category] }
struct Profile: Decodable {
    let committees: [Committee]; let categories: [String]; let alertsEnabled: Bool; let pushConfigured: Bool
}
struct Monitor: Decodable {
    let stale: Bool; let pollIntervalSeconds: Int; let lastSuccessUtc: String?; let unresolvedGaps: Int
}
struct OK: Decodable { let ok: Bool }
struct Registration: Decodable { let id: String }
struct WatchBody: Encodable { let committees: [String]; let categories: [String] }
struct PushBody: Encodable { let enabled: Bool; let token: String?; let environment: String }

// Each installation gets its own unpredictable bearer credential. Never bundled in the app.
enum InstallationKey {
    static let service = "IllinoisTracker.Installation"
    static func credential() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: "credential"]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query.merging([kSecReturnData as String: true]) { _, new in new } as CFDictionary, &result)
        if code == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) { return value }
        guard code == errSecItemNotFound else { throw APIError.message("Unlock your phone to access your watchlist.") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError.message("Could not create a secure installation.") }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        let item = query.merging([kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APIError.message("Could not save this installation securely.") }
        return value
    }
}
enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct API {
    let base = URL(string: "https://illinois-filing-tracker.onrender.com")!
    let credential: String
    func call<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.message("Invalid request.") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw APIError.message(detail ?? "Could not reach the filing service. Please try again.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}

struct ReportContents: Decodable {
    let status: String
    let message: String?
    let contributions: [ReportContribution]?
    let total: String?
    let period: String?
}
struct ReportContribution: Decodable, Identifiable {
    let id: Int
    let contributor: String
    let amount: String
    let receivedDate: String
    let contributionType: String
    let description: String
    let vendor: String
    let address: String
    let vendorAddress: String

    static func currency(_ value: String) -> String {
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return value }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? value
    }
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: receivedDate) else { return receivedDate }
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct CommitteeFinance: Decodable {
    let status: String
    let asOf: String?
    let cashAndInvestments: String?
    let a1Total: String?
    let estimatedCash: String?
    let message: String?
    var estimate: Decimal? { estimatedCash.flatMap { Decimal(string: $0) } }
}
struct FinanceDirectory: Decodable { let committees: [String: CommitteeFinance] }

struct HistoryStatus: Decodable {
    let status: String
    let message: String?
    let total: Int?
    let creationDate: String?
}
