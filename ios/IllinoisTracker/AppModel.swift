import SwiftUI
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var filings: [Filing] = []
    @Published var watched: [Filing] = []
    @Published var committees: [Committee] = []
    @Published var following: [Committee] = []
    @Published var categories: [Category] = []
    @Published var followedCategories: [String] = []
    @Published var monitor: Monitor?
    @Published var error: String?
    @Published var loading = false
    @Published var saving = false
    @Published var pushConfigured = false
    @Published var alertsEnabled = false
    @Published var notificationStatus = "Not enabled"
    @Published var selectedFiling: Filing?
    @Published var allHasMore = false
    @Published var watchedHasMore = false
    @Published var committeesHaveMore = false
    private var allCursor: Int?
    private var watchedCursor: Int?
    private var committeeCursor: String?
    private var searchText = ""
    private var searchGeneration = 0
    private var api: API?
    private var registered = false
    private var acceptingPushRegistration = false
    private var lastRefresh = Date.distantPast

    func connection() throws -> API {
        if let api { return api }
        let result = API(credential: try InstallationKey.credential())
        api = result; return result
    }
    func setup() async throws {
        let api = try connection()
        if !registered {
            let _: Registration = try await api.call("/v1/installations", method: "POST")
            registered = true
        }
    }
    func refresh() async {
        guard !loading, !saving else { return }
        loading = true
        defer { loading = false }
        do {
            try await setup()
            let api = try connection()
            let profile: Profile = try await api.call("/v1/me")
            following = profile.committees; followedCategories = profile.categories
            alertsEnabled = profile.alertsEnabled; pushConfigured = profile.pushConfigured
            monitor = try await api.call("/v1/status")
            let categoryPage: CategoryPage = try await api.call("/v1/categories")
            categories = categoryPage.categories
            let page: FilingPage = try await api.call("/v1/filings")
            filings = page.filings; allCursor = page.nextCursor; allHasMore = page.hasMore
            try await refreshWatched()
            if committees.isEmpty { await search("") }
            lastRefresh = Date()
            await refreshPermission()
        } catch { self.error = error.localizedDescription }
    }
    func refreshIfNeeded() async {
        if Date().timeIntervalSince(lastRefresh) >= 60 { await refresh() }
    }
    func refreshWatched() async throws {
        let page: FilingPage = try await connection().call("/v1/me/filings")
        watched = page.filings; watchedCursor = page.nextCursor; watchedHasMore = page.hasMore
    }
    func loadMore(watchlist: Bool) async {
        guard !loading, let cursor = watchlist ? watchedCursor : allCursor else { return }
        loading = true; defer { loading = false }
        do {
            let page: FilingPage = try await connection().call("\(watchlist ? "/v1/me/filings" : "/v1/filings")?before=\(cursor)")
            if watchlist {
                watched += page.filings.filter { next in !watched.contains(where: { $0.id == next.id }) }
                watchedCursor = page.nextCursor; watchedHasMore = page.hasMore
            } else {
                filings += page.filings.filter { next in !filings.contains(where: { $0.id == next.id }) }
                allCursor = page.nextCursor; allHasMore = page.hasMore
            }
        } catch { self.error = error.localizedDescription }
    }
    func search(_ query: String, more: Bool = false) async {
        searchGeneration += 1
        let generation = searchGeneration
        searchText = query
        var parts = URLComponents(); parts.path = "/v1/committees"
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        if more, let committeeCursor { parts.queryItems?.append(URLQueryItem(name: "after", value: committeeCursor)) }
        do {
            let page: CommitteePage = try await connection().call(parts.string ?? "/v1/committees")
            guard generation == searchGeneration, !Task.isCancelled else { return }
            committees = more ? committees + page.committees : page.committees
            committeeCursor = page.nextCursor; committeesHaveMore = page.hasMore
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func follows(_ committee: Committee) -> Bool { following.contains(where: { $0.id == committee.id }) }
    func toggle(_ committee: Committee) async {
        guard !saving, !loading else { return }
        var next = following
        if follows(committee) { next.removeAll { $0.id == committee.id } } else { next.append(committee) }
        await save(next, categories: followedCategories)
    }
    func toggleCategory(_ id: String) async {
        guard !saving, !loading else { return }
        var next = followedCategories
        if next.contains(id) { next.removeAll { $0 == id } } else { next.append(id) }
        await save(following, categories: next)
    }
    private func save(_ next: [Committee], categories: [String]) async {
        saving = true; defer { saving = false }
        do {
            try await setup()
            let api = try connection()
            let _: OK = try await api.call("/v1/me/watchlist", method: "PUT", body: api.encoded(WatchBody(committees: next.map(\.id), categories: categories)))
            following = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            followedCategories = categories
            try await refreshWatched()
        } catch { self.error = error.localizedDescription }
    }
    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "Allowed on this iPhone"
            if alertsEnabled { acceptingPushRegistration = true; UIApplication.shared.registerForRemoteNotifications() }
        case .denied: notificationStatus = "Disabled in iPhone Settings"
        default: notificationStatus = "Not enabled"
        }
    }
    func enableAlerts() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge])
            if allowed { acceptingPushRegistration = true; UIApplication.shared.registerForRemoteNotifications() }
            else { error = "Allow notifications in iPhone Settings to receive filing alerts." }
            await refreshPermission()
        } catch { self.error = error.localizedDescription }
    }
    func registerPush(_ token: String) async {
        guard acceptingPushRegistration else { return }
        do {
            try await setup()
            let api = try connection()
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            let _: OK = try await api.call("/v1/me/push", method: "PUT", body: api.encoded(PushBody(enabled: true, token: token, environment: environment)))
            alertsEnabled = true
        } catch { self.error = error.localizedDescription }
    }
    func disableAlerts() async {
        acceptingPushRegistration = false
        do {
            let api = try connection()
            let _: OK = try await api.call("/v1/me/push", method: "PUT", body: api.encoded(PushBody(enabled: false, token: nil, environment: "sandbox")))
            alertsEnabled = false
            UIApplication.shared.unregisterForRemoteNotifications()
        } catch { self.error = error.localizedDescription }
    }
    func deleteData() async {
        acceptingPushRegistration = false
        guard !saving, !loading else { return }
        saving = true; defer { saving = false }
        do {
            let _: OK = try await connection().call("/v1/me", method: "DELETE")
            UIApplication.shared.unregisterForRemoteNotifications()
            following = []; followedCategories = []; watched = []; alertsEnabled = false
            registered = false
            // A subsequent explicit follow/refresh registers this installation again, empty.
        } catch { self.error = error.localizedDescription }
    }
    func openNotification(_ seq: Int) async {
        do { selectedFiling = try await connection().call("/v1/filings/\(seq)") }
        catch { self.error = error.localizedDescription }
    }
}
