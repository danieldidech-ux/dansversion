import SwiftUI

private let accent = Color(red: 0.12, green: 0.46, blue: 0.62)
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView().tabItem { Label("Filings", systemImage: "doc.text") }.tag(0)
            CaucusesView().tabItem { Label("Caucuses", systemImage: "person.3") }.tag(1)
            DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }.tag(2)
            WatchlistView().tabItem { Label("Watchlist", systemImage: "star") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-caucuses") { selectedTab = 1 }
            #endif
        }
        .tint(accent)
        .alert("Couldn't finish that", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "Please try again.") }
        .sheet(item: $model.selectedFiling) { filing in NavigationStack { FilingDetail(filing: filing) } }
    }
}
struct FeedView: View {
    @EnvironmentObject var model: AppModel
    @State private var watchOnly = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "waveform.path").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Illinois, on the record.").font(.headline)
                            Text(model.monitor?.stale == true ? "Feed delayed. Showing saved filings." : "Checking for new filings every minute.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if (model.monitor?.unresolvedGaps ?? 0) > 0 { Text("A possible gap in filing history is under review.").font(.caption).foregroundStyle(.orange) }
                        }
                    }.padding(.vertical, 8)
                    Picker("Filings", selection: $watchOnly) {
                        Text("All filings").tag(false); Text("Following").tag(true)
                    }.pickerStyle(.segmented)
                }
                Section {
                    let rows = watchOnly ? model.watched : model.filings
                    if model.loading && rows.isEmpty { ProgressView("Loading filings…") }
                    else if rows.isEmpty {
                        ContentUnavailableView(watchOnly ? "Your watch starts here" : "No filings loaded", systemImage: watchOnly ? "star" : "doc.text", description: Text(watchOnly ? "Follow committees in Discover to see their reports here." : "Pull down to try again."))
                    }
                    ForEach(rows) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) } }
                    if watchOnly ? model.watchedHasMore : model.allHasMore {
                        Button { Task { await model.loadMore(watchlist: watchOnly) } } label: { HStack { Spacer(); Text(model.loading ? "Loading…" : "Load earlier filings"); Spacer() } }.disabled(model.loading)
                    }
                } header: { Text("Latest discoveries") } footer: { Text("Reports and filing dates come from the Illinois State Board of Elections. Dates are displayed as published by the state.") }
            }
            .navigationTitle("Illinois Filings")
            .refreshable { await model.refresh() }
            .toolbar { if model.loading { ProgressView() } }
        }
    }
}
// Shared by feed rows and filing detail headers, including amended reports.
private enum FilingReportKind {
    case a1, d1, quarterly, finalReport, other

    init(_ reportType: String) {
        let value = reportType.uppercased()
            .replacingOccurrences(of: "[‐‑–—−]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ code: String) -> Bool {
            value.range(of: "^" + code + "\\b", options: .regularExpression) != nil
        }
        if matches("A-1") { self = .a1 }
        else if matches("D-1") { self = .d1 }
        else if matches("D-2") && value.contains("FINAL") { self = .finalReport }
        else if matches("D-2") && value.contains("QUARTERLY") { self = .quarterly }
        else { self = .other }
    }

    func color(dark: Bool) -> Color {
        let rgb: (Double, Double, Double)
        switch self {
        case .a1: rgb = dark ? (140, 200, 255) : (21, 87, 160)
        case .d1: rgb = dark ? (212, 172, 255) : (113, 61, 163)
        case .quarterly: rgb = dark ? (124, 225, 192) : (8, 107, 84)
        case .finalReport: rgb = dark ? (255, 189, 128) : (154, 75, 0)
        case .other: return .secondary
        }
        return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }
}

private struct ReportTypeBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let reportType: String
    private var color: Color { FilingReportKind(reportType).color(dark: colorScheme == .dark) }

    var body: some View {
        Text(reportType.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("Report type: \(reportType)")
    }
}

struct FilingRow: View {
    let filing: Filing
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ReportTypeBadge(reportType: filing.reportType)
            Text(filing.committeeName).font(.headline).foregroundStyle(.primary)
            if let date = filing.publishedRaw { Text(date).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
}
struct FilingDetail: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    var committee: Committee { Committee(id: filing.committeeKey, name: filing.committeeName) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FilingRow(filing: filing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                NativeReportContents(filing: filing).id(filing.seq)

                VStack(spacing: 0) {
                    Button { Task { await model.toggle(committee) } } label: {
                        Label(model.follows(committee) ? "Unfollow committee" : "Follow committee",
                              systemImage: model.follows(committee) ? "star.fill" : "star")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }.disabled(model.saving || model.loading)
                    if let url = filing.reportURL {
                        Divider().padding(.leading, 18)
                        Link(destination: url) {
                            Label("Open official report", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        }
                    }
                }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                Text("Following applies to all report types filed by this committee. Alerts begin with newly discovered filings after you follow and enable notifications.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Filing").navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeReportContents: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    @State private var report: ReportContents?
    @State private var failure: String?
    @State private var loading = true
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report contents").font(.headline)
            if loading {
                ProgressView("Loading contributions…")
                    .frame(maxWidth: .infinity).padding(24)
            } else if let report, report.status == "ready", let contributions = report.contributions, !contributions.isEmpty {
                if contributions.count > 1 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(contributions.count) contributions").font(.subheadline)
                        Spacer()
                        if let total = report.total { Text(ReportContribution.currency(total)).font(.headline) }
                    }
                    Text("Total reported value, including any in-kind contributions")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(contributions) { contribution in
                    ContributionCard(contribution: contribution)
                }
                Text("Source: Illinois State Board of Elections")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Report details unavailable", systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text(failure ?? report?.message ?? "Open the official report below to read this filing.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if report?.status != "unsupported" {
                        Button("Try again") { attempt += 1 }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }.task(id: attempt) { await load() }
    }

    @MainActor private func load() async {
        loading = true; failure = nil; report = nil
        do {
            try await model.setup()
            let result: ReportContents = try await model.connection().call("/v1/filings/\(filing.seq)/contents")
            try Task.checkCancellation()
            report = result
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
        loading = false
    }
}

private struct ContributionCard: View {
    let contribution: ReportContribution
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ReportContribution.currency(contribution.amount))
                    .font(.largeTitle.weight(.bold)).foregroundStyle(accent)
                    .accessibilityLabel("Contribution value \(ReportContribution.currency(contribution.amount))")
                Text("from").font(.subheadline).foregroundStyle(.secondary)
                Text(contribution.contributor).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
            Text(contribution.contributionType)
                .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            detail("Received", contribution.displayDate)
            if !contribution.description.isEmpty { detail("Description", contribution.description) }
            if !contribution.vendor.isEmpty { detail("Vendor", contribution.vendor) }
            if !contribution.address.isEmpty || !contribution.vendorAddress.isEmpty {
                DisclosureGroup("Addresses") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !contribution.address.isEmpty { detail("Contributor address", contribution.address) }
                        if !contribution.vendorAddress.isEmpty { detail("Vendor address", contribution.vendorAddress) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.subheadline)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ForEach(model.categories) { category in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.name)
                                    Text(category.verified == 1 ? "\(category.memberCount) committees" : "Committee list under review").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if category.verified == 1 {
                                    Button { Task { await model.toggleCategory(category.id) } } label: { Image(systemName: model.followedCategories.contains(category.id) ? "checkmark.circle.fill" : "plus.circle") }
                                        .buttonStyle(.borderless).disabled(model.saving || model.loading)
                                } else { Image(systemName: "clock").foregroundStyle(.secondary) }
                            }
                        }
                    } header: { Text("Follow a group") } footer: { Text("Groups follow the current curated committee lists. Browse their members and candidates in Caucuses. Lists may be revised over time.") }
                }
                Section {
                    ForEach(model.committees) { committee in
                        HStack(spacing: 12) {
                            Text(committee.name)
                            Spacer()
                            Button { Task { await model.toggle(committee) } } label: { Image(systemName: model.follows(committee) ? "checkmark.circle.fill" : "plus.circle").font(.title3) }
                                .buttonStyle(.borderless).disabled(model.saving || model.loading)
                                .accessibilityLabel("\(model.follows(committee) ? "Unfollow" : "Follow") \(committee.name)")
                        }.padding(.vertical, 4)
                    }
                    if model.committees.isEmpty { Text("No matching committees. Try another name.").foregroundStyle(.secondary) }
                    if model.committeesHaveMore { Button("Load more committees") { Task { await model.search(query, more: true) } } }
                } header: { Text("Committees") } footer: { Text("Includes the legislative directory and committees observed in the monitored feed. This is not the complete statewide directory.") }
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Find a committee")
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(300)); await model.search(query) } catch { }
            }
        }
    }
}
struct WatchlistView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.alertsEnabled && model.pushConfigured ? "Filing alerts enabled" : "Manage alerts in Settings", systemImage: model.alertsEnabled && model.pushConfigured ? "bell.badge" : "bell")
                }
                if model.following.isEmpty && model.followedCategories.isEmpty {
                    ContentUnavailableView("Keep an eye on the money", systemImage: "star", description: Text("Add committees from Discover. Every report type is included."))
                }
                if !model.followedCategories.isEmpty {
                    Section("Groups") {
                        ForEach(model.categories.filter { model.followedCategories.contains($0.id) }) { category in
                            HStack { Text(category.name); Spacer(); Button("Unfollow") { Task { await model.toggleCategory(category.id) } }.buttonStyle(.borderless).disabled(model.saving || model.loading) }
                        }
                    }
                }
                Section("Committees · \(model.following.count)") {
                    ForEach(model.following) { committee in
                        HStack { Text(committee.name); Spacer(); Button { Task { await model.toggle(committee) } } label: { Image(systemName: "star.fill") }.buttonStyle(.borderless).disabled(model.saving || model.loading).accessibilityLabel("Unfollow \(committee.name)") }
                    }
                }
            }.navigationTitle("Watchlist").refreshable { await model.refresh() }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            List {
                Section("Filing alerts") {
                    Label(model.notificationStatus, systemImage: "bell")
                    if !model.pushConfigured {
                        Text("Push delivery is waiting for Apple Developer setup. You can follow committees and browse reports now.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if model.alertsEnabled {
                        Button("Pause filing alerts") { Task { await model.disableAlerts() } }
                    } else {
                        Button("Enable filing alerts") { Task { await model.enableAlerts() } }.disabled(!model.pushConfigured)
                    }
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("Open iPhone Settings", destination: url) }
                }
                Section("About") {
                    Text("Illinois Filing Tracker").font(.headline)
                    Text("An independent way to follow Illinois campaign finance filings. Not affiliated with the Illinois State Board of Elections.").font(.subheadline)
                    Link("Official filing feed", destination: URL(string: "https://www.elections.il.gov/rss/LatestReportsFiled.aspx")!)
                    Text("The service checks every minute. State publication delays, connection issues, and iPhone notification settings can affect alert timing.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    Text("No email or password required. Your installation identifier, followed committees and groups, and push token are stored to deliver your alerts. Your watchlist belongs to this installation and does not sync between devices.").font(.subheadline)
                    Button("Delete my watchlist and notification data", role: .destructive) { confirmDelete = true }.disabled(model.saving || model.loading)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete your saved watchlist and disable alerts?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my data", role: .destructive) { Task { await model.deleteData() } }
            }
        }
    }
}

struct CaucusesView: View {
    @EnvironmentObject var model: AppModel
    @State private var directory: CaucusDirectory?
    @State private var chamber = "house"
    @State private var party = "democrats"
    @AppStorage("caucusSort") private var sortOrder = "name"
    @State private var finances: [String: CommitteeFinance] = [:]
    @State private var loading = false
    @State private var failure: String?
    private var groupID: String { "\(chamber)-\(party)" }
    private var group: CaucusGroup? { directory?.groups.first { $0.id == groupID } }
    private var members: [DirectoryEntry] {
        guard let group else { return [] }
        let pinned = Set(group.pinned.compactMap { $0.committee?.id })
        return group.members.filter { row in
            guard let committee = row.committee else { return true }
            return !pinned.contains(committee.id)
        }.sorted {
            if sortOrder == "cash" {
                let a = finances[$0.committee?.id ?? ""]?.estimate
                let b = finances[$1.committee?.id ?? ""]?.estimate
                if a != b {
                    if let a, let b { return a > b }
                    return a != nil
                }
            }
            if sortOrder == "district", $0.district != $1.district { return ($0.district ?? 999) < ($1.district ?? 999) }
            let comparison = $0.lastName.localizedStandardCompare($1.lastName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.member.localizedStandardCompare($1.member) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Chamber", selection: $chamber) {
                        Text("House").tag("house"); Text("Senate").tag("senate")
                    }.pickerStyle(.segmented)
                    Picker("Party", selection: $party) {
                        Text("Democrats").tag("democrats"); Text("Republicans").tag("republicans")
                    }.pickerStyle(.segmented)
                    Picker("Sort by", selection: $sortOrder) {
                        Text("Last name").tag("name")
                        Text("District number").tag("district")
                        Text("Estimated cash on hand").tag("cash")
                    }
                }
                if let failure {
                    Section {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                    }
                }
                if let group {
                    Section {
                        Button {
                            Task { await model.toggleCategory(group.id) }
                        } label: {
                            Label(model.followedCategories.contains(group.id) ? "Following \(group.name)" : "Follow \(group.name)", systemImage: model.followedCategories.contains(group.id) ? "star.fill" : "star")
                        }.disabled(model.saving || model.loading)
                    } footer: { Text("Follow all listed committees, including the leader and caucus funds. Membership updates apply automatically.") }
                    if sortOrder == "cash" {
                        Section {
                            Text("Highest estimates first. Unavailable estimates appear last. Balances may use different quarter-end dates; pull to refresh as summaries finish loading.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Leader & caucus committees") {
                        ForEach(group.pinned) { entry in directoryRow(entry) }
                    }
                    Section {
                        ForEach(members) { entry in directoryRow(entry) }
                    } header: { Text("Members & candidates") }
                    footer: { Text("The directory includes selected current-cycle candidates as well as sitting members. Committee lists may be revised.") }
                } else if loading { ProgressView("Loading committees…") }
            }
            .navigationTitle(group?.name ?? "Caucuses")
            .navigationBarTitleDisplayMode(.inline)
            .task { if directory == nil { await load() } }
            .task(id: groupID) {
                while !Task.isCancelled {
                    await loadFinances()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .refreshable { await load(); await loadFinances() }
        }
    }
    @ViewBuilder private func directoryRow(_ entry: DirectoryEntry) -> some View {
        if let committee = entry.committee {
            NavigationLink {
                CommitteeFilingsView(committee: committee, member: entry.member, officialURL: entry.officialURL)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    if !entry.member.isEmpty {
                        Text(entry.member).font(.headline)
                    }
                    Text(committee.name).font(entry.member.isEmpty ? .headline : .subheadline)
                    if sortOrder == "cash" {
                        if let value = finances[committee.id]?.estimatedCash {
                            Text("Est. " + ReportContribution.currency(value)).font(.subheadline.bold()).foregroundStyle(accent)
                        } else { Text("Estimate unavailable").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let district = entry.district {
                        Text("District \(district)").font(.caption).foregroundStyle(.secondary)
                    } else if entry.role == "Leader" {
                        Text("Chamber leader").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 3)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.member).font(.headline)
                if let district = entry.district { Text("District \(district)").font(.caption) }
                Text("Committee to be added").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    @MainActor private func loadFinances() async {
        let requestedGroup = groupID
        do {
            let amounts: FinanceDirectory = try await model.connection().call("/v1/committee-finances?group=\(requestedGroup)")
            guard !Task.isCancelled else { return }
            finances.merge(amounts.committees) { _, new in new }
        } catch { /* Keep verified saved amounts while retrying. */ }
    }
    @MainActor private func load() async {
        guard !loading else { return }
        loading = true; failure = nil
        defer { loading = false }
        do {
            let result: CaucusDirectory = try await model.connection().call("/v1/directory")
            try Task.checkCancellation()
            directory = result

        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
}

struct CommitteeFinanceCard: View {
    let finance: CommitteeFinance?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial summary").font(.headline)
            if let date = finance?.asOf { Text("As of quarter ending \(date)").font(.caption).foregroundStyle(.secondary) }
            amount("Cash on hand + investments", finance?.cashAndInvestments)
            amount("A-1s since quarter end", finance?.a1Total)
            Divider()
            amount("Estimated cash on hand", finance?.estimatedCash)
            Text(finance?.message ?? "Loading financial summary…").font(.caption).foregroundStyle(.secondary)
            Text("Estimate adds reported A-1 amounts to the quarterly balance. It does not subtract later spending or include smaller unreported contributions; A-1s may include noncash contributions.").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
    private func amount(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label); Spacer()
            Text(value.map { ReportContribution.currency($0) } ?? "Unavailable").bold().monospacedDigit()
        }
    }
}

struct CommitteeFilingsView: View {
    @EnvironmentObject var model: AppModel
    let committee: Committee
    let member: String
    let officialURL: URL?
    @State private var filings: [Filing] = []
    @State private var finance: CommitteeFinance?
    @State private var history: HistoryStatus?
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false
    @State private var failure: String?
    var body: some View {
        List {
            Section { CommitteeFinanceCard(finance: finance) }
            Section {
                if !member.isEmpty { Text(member).font(.headline) }
                Text(committee.name).font(.title3.bold())
                Button {
                    Task { await model.toggle(committee) }
                } label: {
                    Label(model.follows(committee) ? "Following committee" : "Follow committee", systemImage: model.follows(committee) ? "star.fill" : "star")
                }.disabled(model.saving || model.loading)
            }
            Section("Reports") {
                if let history {
                    if history.status == "ready", let total = history.total {
                        Text("\(total) reports · Since \(history.creationDate ?? "committee creation")").font(.caption).foregroundStyle(.secondary)
                    } else { Text(history.message ?? "Loading history…").font(.caption).foregroundStyle(.secondary) }
                }
                if let failure {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load(more: false) } }
                }
                ForEach(filings) { filing in
                    NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) }
                }
                if loading { ProgressView("Loading reports…") }
                else if loaded && filings.isEmpty && failure == nil && history?.status == "ready" {
                    Text("No reports from this committee have been collected yet. Follow it to track new filings.").foregroundStyle(.secondary)
                }
                if hasMore {
                    ProgressView("Loading earlier reports…")
                        .task { await load(more: true) }
                        .id(cursor)
                }
            }
            if let officialURL {
                Section { Link("Open official committee page", destination: officialURL) }
            }
        }
        .navigationTitle("Committee")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load(more: false)
            while !Task.isCancelled && (history?.status == "loading" || finance?.status == "loading") {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if history?.status == "loading" { await load(more: false) }
                else { finance = try? await model.connection().call("/v1/committees/\(committee.id)/finance") }
            }
        }
        .refreshable { await load(more: false) }
    }
    @MainActor private func load(more: Bool) async {
        guard !loading else { return }
        loading = true; failure = nil
        defer { loading = false }
        var parts = URLComponents(); parts.path = "/v1/committees/\(committee.id)/history"
        parts.queryItems = []
        if more, let cursor { parts.queryItems?.append(URLQueryItem(name: "before", value: String(cursor))) }
        do {
            let page: FilingPage = try await model.connection().call(parts.string ?? "/v1/filings")
            try Task.checkCancellation()
            if more { filings += page.filings.filter { next in !filings.contains { $0.id == next.id } } }
            else { filings = page.filings }
            cursor = page.nextCursor; hasMore = page.hasMore; loaded = true; history = page.history
            if !more { finance = try await model.connection().call("/v1/committees/\(committee.id)/finance") }
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
}
