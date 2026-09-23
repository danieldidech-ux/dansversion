import Foundation
import Security

struct Filing: Codable, Identifiable, Hashable {
    let seq: Int
    let committeeKey: String
    let committeeName: String
    let reportType: String
    let publishedRaw: String?
    let url: String?
    var preview: FilingPreview? = nil
    var displayDate: String {
        guard let raw = publishedRaw else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss", "EEE, d MMM yyyy HH:mm:ss"] {
            f.dateFormat = format
            if let date = f.date(from: raw) { f.dateFormat = "MMM d, yyyy · h:mm a"; return f.string(from: date) }
        }
        return raw
    }
    var id: Int { seq }
    var reportURL: URL? {
        guard let url, let result = URL(string: url), result.scheme == "https",
              ["www.elections.il.gov", "elections.il.gov"].contains(result.host ?? "") else { return nil }
        return result
    }
}
struct Committee: Codable, Identifiable, Hashable { let id: String; let name: String }
struct CaucusDirectory: Decodable {
    let revision: String
    let groups: [CaucusGroup]
    var skippedEntries: Int { groups.reduce(0) { $0 + $1.skippedEntries } }
}
struct CaucusGroup: Decodable, Identifiable {
    let id: String
    let name: String
    let pinned: [DirectoryEntry]
    let members: [DirectoryEntry]
    let skippedEntries: Int
    enum CodingKeys: String, CodingKey { case id, name, pinned, members }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        func rows(_ key: CodingKeys) throws -> ([DirectoryEntry], Int) {
            var values = try c.nestedUnkeyedContainer(forKey: key)
            var result: [DirectoryEntry] = []; var skipped = 0
            while !values.isAtEnd {
                let item = try values.superDecoder()
                do { result.append(try DirectoryEntry(from: item)) } catch { skipped += 1 }
            }
            return (result, skipped)
        }
        let a = try rows(.pinned), b = try rows(.members)
        pinned = a.0; members = b.0; skippedEntries = a.1 + b.1
    }
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
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cacheable = method == "GET" && (path == "/v1/directory" || path == "/v1/filings" || path.contains("/history") || path.contains("/finance") || path.contains("/contents") || path.contains("/schedules/"))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode >= 500 { throw URLError(.badServerResponse) }
            guard (200..<300).contains(response.statusCode) else {
                let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
                throw APIError.message(detail ?? "Could not load this request. Please try again.")
            }
            let result = try decoder.decode(T.self, from: data)
            if cacheable {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let status = json?["status"] as? String
                if let status, ["unavailable", "loading"].contains(status), let saved = ResponseCache.read(path) {
                    ResponseCache.setStale(path, true)
                    return try decoder.decode(T.self, from: saved)
                }
                if status == nil || status == "ready" {
                    if let directory = result as? CaucusDirectory, directory.skippedEntries > 0 {
                        ResponseCache.setStale(path, true)
                    } else { ResponseCache.save(data, path: path) }
                }
            }
            return result
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            if cacheable, !(error is APIError), let data = ResponseCache.read(path) {
                let saved = try decoder.decode(T.self, from: data)
                ResponseCache.setStale(path, true)
                return saved
            }
            throw error
        }
    }
    func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}

struct ReportContents: Decodable {
    let status: String
    let message: String?
    let kind: String?
    let summary: [String: String]?
    let sections: [QuarterlySection]?
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
    let entityId: String?
    let disclosureId: String?

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
    let monetaryReceipts: String?
    let inKindTotal: String?
    let checkedAt: Double?
    let stale: Bool?
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

struct QuarterlySection: Decodable, Identifiable {
    let id: String
    let title: String
    let group: String
    let itemized: String
    let unitemized: String
    let hasDetails: Bool
    let sourceUrl: String?
}
struct ItemizedSchedule: Decodable {
    let status: String
    let message: String?
    let title: String?
    let period: String?
    let entries: [ScheduleEntry]?
    let total: Int?
}
struct ScheduleEntry: Decodable, Identifiable {
    let id: Int
    let fields: [ScheduleField]
    let entityId: String?
}
struct ScheduleField: Decodable {
    let label: String
    let value: String
}

struct ObserverList: Decodable, Identifiable {
    let id: String; let name: String; let committees: [Committee]; let donors: [Entity]; let newCount: Int; let seenSeq: Int
}
struct ObserverLists: Decodable { let lists: [ObserverList] }
struct CreatedList: Decodable { let id: String }
struct Entity: Decodable, Identifiable { let id: String; let name: String; let address: String }
struct EntitySearch: Decodable { let entities: [Entity]; let coverage: String?; let hasMore: Bool? }
struct Disclosure: Decodable, Identifiable {
    let id: String; let committeeKey: String; let committeeName: String; let seq: Int
    let amount: String; let date: String; let kind: String; let sourceUrl: String
}
struct EntityHistory: Decodable {
    let entity: Entity; let disclosures: [Disclosure]; let hasMore: Bool; let nextOffset: Int
    let coverage: String; let committee: Committee?
}
struct AlertPreferences: Codable {
    var mode = "all"; var minimum = "0"; var delivery = "instant"; var quiet = false
    var quietStart = 22; var quietEnd = 7; var timezone = "America/Chicago"
}

// Public report data only. Private lists and installation credentials are never cached here.
enum ResponseCache {
    static func key(_ path: String) -> String { Data(path.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") }
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VerifiedReports", isDirectory: true)
    }
    static func save(_ data: Data, path: String) {
        guard data.count < 5_000_000 else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key(path)), options: .atomic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "checked:" + path)
        setStale(path, false)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        if files.count > 250 {
            let sorted = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for file in sorted.prefix(files.count - 250) { try? FileManager.default.removeItem(at: file) }
        }
    }
    static func read(_ path: String) -> Data? { try? Data(contentsOf: directory.appendingPathComponent(key(path))) }
    static func setStale(_ path: String, _ stale: Bool) {
        UserDefaults.standard.set(stale, forKey: "stale:" + path)
        DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("reportCacheChanged"), object: path) }
    }
}

struct FilingPreview: Codable, Hashable {
    let kind: String
    let total: String?
    let contributionCount: Int?
    let contributors: [String]?
    let contributorCount: Int?
    let period: String?
    let receipts: String?
    let expenditures: String?
    let endingCash: String?
}
struct ProblemReceipt: Decodable { let id: String }
