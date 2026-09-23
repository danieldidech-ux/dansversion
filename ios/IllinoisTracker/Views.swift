import SwiftUI

private enum CivicTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    private static var pink: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-pink") { return true }
        #endif
        return UserDefaults.standard.string(forKey: "appearance") == "pink"
    }
    static var background: Color { pink ? adaptive(0xFFF2F6, 0xFFF2F6) : adaptive(0xF3F6FA, 0x10191F) }
    static var surface: Color { pink ? adaptive(0xFFFFFF, 0xFFFFFF) : adaptive(0xFFFFFF, 0x19262F) }
    static var ink: Color { pink ? adaptive(0x482237, 0x482237) : adaptive(0x102A43, 0xEEF5F8) }
    static var accent: Color { pink ? adaptive(0x96375F, 0x96375F) : adaptive(0x006078, 0x9FE8EE) }
    static var summary: Color { pink ? adaptive(0x662740, 0x662740) : adaptive(0x082E45, 0x192C36) }
    static var summaryNumber: Color { pink ? .white : adaptive(0xFFFFFF, 0x9FE8EE) }
}
private var accent: Color { CivicTheme.accent }

private extension View {
    func civicSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .background(CivicTheme.background)
            .foregroundStyle(CivicTheme.ink)
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 44)
            .modifier(PreviewTextScale())
    }
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab = 0
    @AppStorage("appearance") private var appearance = "light"
    private var preferredScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-night") { return .dark }
        #endif
        return appearance == "system" ? nil : (appearance == "dark" ? .dark : .light)
    }
    var body: some View {
        Group {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-problem") {
            NavigationStack { ProblemForm(context: ["screen": "Filing", "committee": "Example committee"]) }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-alert-options") {
            NavigationStack { AlertOptionsView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-lists") {
            NavigationStack { MyListsView() }

        } else if ProcessInfo.processInfo.arguments.contains("--preview-committee") {
            NavigationStack { CommitteeFilingsView(committee: Committee(id: "1b5ce79b8d1251adaf13eda719fd6d7a", name: "Daniel Didech Campaign Committee"), member: "Daniel Didech", officialURL: nil) }.tint(accent)
        } else if ProcessInfo.processInfo.arguments.contains("--preview-quarter") {
            NavigationStack { FilingDetail(filing: previewQuarter) }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-schedule") {
            NavigationStack { QuarterlySchedulePreview(filing: previewQuarter) }
        } else { mainTabs }
        #else
        mainTabs
        #endif
        }.id(appearance).preferredColorScheme(preferredScheme).tint(accent)
    }
    #if DEBUG
    private var previewQuarter: Filing {
        Filing(seq: -19, committeeKey: "1b5ce79b8d1251adaf13eda719fd6d7a", committeeName: "Daniel Didech Campaign Committee", reportType: "D-2 Quarterly Report", publishedRaw: "July 15, 2026", url: nil)
    }
    #endif
    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView().tabItem { Label("Home", systemImage: "house") }.tag(0)
            FeedView().tabItem { Label("Latest Reports", systemImage: "doc.text") }.tag(1)
            DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }.tag(2)
            WatchlistView().tabItem { Label("Watchlist", systemImage: "star") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-reports") { selectedTab = 1 }
            #endif
        }
        .tint(accent)
        .alert("Couldn't finish that", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "Please try again.") }
        .sheet(isPresented: $model.showAlertInbox) { NavigationStack { AlertInboxView() } }
        .sheet(item: $model.selectedFiling) { filing in NavigationStack { FilingDetail(filing: filing) } }
    }
}
private enum HomeCaucus: String, CaseIterable, Identifiable {
    case executive = "executive-branch"
    case houseDemocrats = "house-democrats"
    case senateDemocrats = "senate-democrats"
    case houseRepublicans = "house-republicans"
    case senateRepublicans = "senate-republicans"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .executive: return "Executive Branch"
        case .houseDemocrats: return "House Democrats"
        case .senateDemocrats: return "Senate Democrats"
        case .houseRepublicans: return "House Republicans"
        case .senateRepublicans: return "Senate Republicans"
        }
    }
    var chamber: String {
        switch self {
        case .executive: return "Executive"
        case .houseDemocrats, .houseRepublicans: return "House"
        case .senateDemocrats, .senateRepublicans: return "Senate"
        }
    }
    var party: String {
        switch self {
        case .executive: return "Branch"
        case .houseDemocrats, .senateDemocrats: return "Democrats"
        case .houseRepublicans, .senateRepublicans: return "Republicans"
        }
    }
    var colors: [Color] {
        switch self {
        case .executive: return [CivicTheme.adaptive(0xCCBA87, 0xBAA777), CivicTheme.adaptive(0xB19A63, 0xA18C5E)]
        case .houseDemocrats: return [CivicTheme.adaptive(0x1766D5, 0x144FA8), CivicTheme.adaptive(0x123580, 0x102658)]
        case .senateDemocrats: return [CivicTheme.adaptive(0x087BA8, 0x096284), CivicTheme.adaptive(0x17429D, 0x142F68)]
        case .houseRepublicans: return [CivicTheme.adaptive(0xD33149, 0xA8253D), CivicTheme.adaptive(0x86192F, 0x60182B)]
        case .senateRepublicans: return [CivicTheme.adaptive(0xBC4334, 0x983329), CivicTheme.adaptive(0x8D2048, 0x631C35)]
        }
    }
    var foreground: Color {
        self == .executive ? CivicTheme.adaptive(0x382900, 0x382900) : .white
    }

}

struct HomeView: View {
    @State private var path: [HomeCaucus] = []
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(HomeCaucus.allCases) { caucus in
                        NavigationLink(value: caucus) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(caucus.chamber)
                                        .font(.system(.title, design: .rounded, weight: .bold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(caucus.party)
                                        .font(.system(.title, design: .rounded, weight: .bold))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 38, height: 38)
                                    .background(.white.opacity(0.16), in: Circle())
                            }
                            .foregroundStyle(caucus.foreground)
                            .padding(.horizontal, 24).padding(.vertical, 22)
                            .frame(maxWidth: .infinity, minHeight: 125, alignment: .leading)
                            .background {
                                ZStack(alignment: .trailing) {
                                    LinearGradient(colors: caucus.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Circle().stroke(.white.opacity(0.09), lineWidth: 1)
                                        .frame(width: 210, height: 210).offset(x: 65, y: -35)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .overlay {
                                RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: caucus.colors.last!.opacity(0.20), radius: 10, x: 0, y: 6)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(caucus.title)
                            .accessibilityHint("Opens the committee list")
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(CivicTheme.background)
            .navigationTitle("Illinois Committees")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeCaucus.self) { caucus in
                CaucusesView(groupID: caucus.rawValue, title: caucus.title)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-caucuses"), path.isEmpty {
                    path = [.houseDemocrats]
                }
                #endif
            }
        }
    }
}

struct FeedView: View {
    @EnvironmentObject var model: AppModel
    @State private var watchOnly = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.monitor?.stale == true { Label("Feed delayed · showing saved reports", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if (model.monitor?.unresolvedGaps ?? 0) > 0 { Text("A possible gap in filing history is under review.").font(.caption).foregroundStyle(.orange) }
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
                }
            }
            .listSectionSpacing(.compact).contentMargins(.top, 0, for: .scrollContent)
            .civicSurface().navigationTitle("Latest Reports").navigationBarTitleDisplayMode(.inline)
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

    var title: String {
        switch self { case .a1: return "A-1 · Contributions"; case .d1: return "D-1 · Organization"; case .quarterly: return "D-2 · Quarterly"; case .finalReport: return "D-2 · Final"; case .other: return "Report" }
    }
    func color(dark: Bool) -> Color {
        let rgb: (Double, Double, Double)
        switch self {
        case .a1: rgb = dark ? (125, 227, 177) : (15, 111, 67)
        case .d1: rgb = dark ? (212, 172, 255) : (113, 61, 163)
        case .quarterly: rgb = dark ? (140, 200, 255) : (21, 87, 160)
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
        Text((FilingReportKind(reportType) == .other ? reportType : FilingReportKind(reportType).title) + (reportType.localizedCaseInsensitiveContains("amend") ? " · AMENDED" : ""))
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
    var showPreview = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportTypeBadge(reportType: filing.reportType)
            Text(filing.committeeName).font(.headline).foregroundStyle(CivicTheme.ink)
            if showPreview, let p = filing.preview {
                if p.kind == "a1" {
                    if let total = p.total { Text(ReportContribution.currency(total)).font(.title3.bold()).monospacedDigit().foregroundStyle(accent) }
                    if let names = p.contributors { Text(names.joined(separator: " • ") + ((p.contributorCount ?? 0) > names.count ? " + \((p.contributorCount ?? 0) - names.count) more" : "")).font(.subheadline).foregroundStyle(.primary) }
                    Text("\(p.contributionCount ?? 0) contributions · includes reported in-kind value").font(.caption).foregroundStyle(.secondary)
                } else if p.kind == "quarterly" {
                    if let period = p.period { Text(period).font(.subheadline).foregroundStyle(.secondary) }
                    previewMetric("Receipts", p.receipts)
                    previewMetric("Spending", p.expenditures)
                    previewMetric("Ending cash", p.endingCash)
                }
            } else if showPreview && (FilingReportKind(filing.reportType) == .a1 || FilingReportKind(filing.reportType) == .quarterly) {
                Text("Summary not yet available").font(.caption).foregroundStyle(.secondary)
            }
            if !filing.displayDate.isEmpty { Text(filing.displayDate).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
    private func previewMetric(_ label: String, _ value: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(label); Spacer(minLength: 10); Text(value.map { ReportContribution.currency($0) } ?? "Unavailable").bold().monospacedDigit() }
            VStack(alignment: .leading) { Text(label); Text(value.map { ReportContribution.currency($0) } ?? "Unavailable").bold().monospacedDigit() }
        }.font(.subheadline).foregroundStyle(CivicTheme.ink)
    }
}
struct FilingDetail: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    var committee: Committee { Committee(id: filing.committeeKey, name: filing.committeeName) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FilingRow(filing: filing, showPreview: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))

                NativeReportContents(filing: filing).id(filing.seq)
                CacheNotice(path: "/v1/filings/\(filing.seq)/contents")
                ShareLink("Share report", item: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq)")!)
                Link("Export report CSV", destination: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq).csv")!)
                NavigationLink("Add committee to a private list") { AddCommitteeToList(committee: committee) }

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
                }.background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                ProblemButton(context: ["screen": "Filing", "committee": filing.committeeName, "committee_id": filing.committeeKey, "filing_id": String(filing.seq), "source_url": filing.url ?? ""])
                Text("Following applies to all report types filed by this committee. Alerts begin with newly discovered filings after you follow and enable notifications.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }.background(CivicTheme.background)
            .civicSurface().navigationTitle("Filing").navigationBarTitleDisplayMode(.inline)
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
                ProgressView("Loading report…")
                    .frame(maxWidth: .infinity).padding(24)
            } else if let report, report.status == "ready", report.kind == "quarterly" {
                QuarterlyReportView(filing: filing, report: report)
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
                    .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                    .font(.largeTitle.weight(.bold)).monospacedDigit().foregroundStyle(accent)
                    .accessibilityLabel("Contribution value \(ReportContribution.currency(contribution.amount))")
                Text("from").font(.subheadline).foregroundStyle(.secondary)
                Text(contribution.contributor).font(.title3.weight(.semibold)).textSelection(.enabled)
                if let id = contribution.disclosureId {
                    ShareLink("Share contribution", item: URL(string: "https://illinois-filing-tracker.onrender.com/share/transaction/\(id)")!)
                }
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
            .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                    } header: { Text("Follow a group") } footer: { Text("Groups follow the current curated committee lists. Browse their members and candidates from Home. Lists may be revised over time.") }
                }
                Section {
                    ForEach(model.committees) { committee in
                        HStack(spacing: 12) {
                            NavigationLink { CommitteeFilingsView(committee: committee, member: "", officialURL: nil) } label: { Text(committee.name) }
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
            .civicSurface().navigationTitle("Discover")
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
                    NavigationLink("My private lists") { MyListsView() }
                    NavigationLink("Delivered alerts & digests") { AlertInboxView() }
                }
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
                        HStack { NavigationLink { CommitteeFilingsView(committee: committee, member: "", officialURL: nil) } label: { Text(committee.name) }; Spacer(); Button { Task { await model.toggle(committee) } } label: { Image(systemName: "star.fill") }.buttonStyle(.borderless).disabled(model.saving || model.loading).accessibilityLabel("Unfollow \(committee.name)") }
                    }
                }
            }.civicSurface().navigationTitle("Watchlist").refreshable { await model.refresh() }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false
    @AppStorage("appearance") private var appearance = "light"
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("Modern Civic · Light").tag("light")
                        Text("Night Ledger · Dark").tag("dark")
                        Text("Pink Mode").tag("pink")
                        Text("Follow iPhone appearance").tag("system")
                    }
                } header: { Text("Appearance") } footer: {
                    Text("Modern Civic is the default. Choose Night Ledger, Pink Mode, or switch between light and dark with your iPhone.")
                }
                Section("Filing alerts") {
                    NavigationLink("Alert filters, digests & quiet hours") { AlertOptionsView() }
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
                Section("Help") { ProblemButton(context: ["screen": "Settings"]) }
                Section("About") {
                    Text("Illinois Filing Tracker").font(.headline)
                    Text("An independent way to follow Illinois campaign finance filings. Not affiliated with the Illinois State Board of Elections.").font(.subheadline)
                    Link("Official filing feed", destination: URL(string: "https://www.elections.il.gov/rss/LatestReportsFiled.aspx")!)
                    Text("The service checks every minute. State publication delays, connection issues, and iPhone notification settings can affect alert timing.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your data") {
                    Text("No email or password required. Your installation identifier, followed committees and groups, and push token are stored to deliver your alerts. Problem reports you submit are also stored for review. Your watchlist belongs to this installation and does not sync between devices.").font(.subheadline)
                    Button("Delete my saved data", role: .destructive) { confirmDelete = true }.disabled(model.saving || model.loading)
                }
            }
            .civicSurface().navigationTitle("Settings")
            .confirmationDialog("Delete your saved watchlist and disable alerts?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my data", role: .destructive) { Task { await model.deleteData() } }
            }
        }
    }
}

struct CaucusesView: View {
    @EnvironmentObject var model: AppModel
    @State private var directory: CaucusDirectory?
    let groupID: String
    let title: String
    @AppStorage("caucusSort") private var sortOrder = "name"
    @State private var finances: [String: CommitteeFinance] = [:]
    @State private var showInfo = false
    @AppStorage("stale:/v1/directory") private var directoryStale = false
    @State private var loading = false
    @State private var failure: String?
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
            List {
                Section {
                    HStack(spacing: 16) {
                        Menu {
                            Picker("Sort by", selection: $sortOrder) {
                                Text("Last name").tag("name")
                                if groupID != "executive-branch" { Text("District number").tag("district") }
                                Text("Estimated cash on hand").tag("cash")
                            }
                        } label: {
                            Label(sortOrder == "cash" ? "Est. cash" : sortOrder == "district" ? "District" : "Last name", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.semibold))
                        }.accessibilityLabel("Sort committees")
                        Spacer(minLength: 0)
                        if let group {
                            Button { Task { await model.toggleCategory(group.id) } } label: {
                                Label(model.followedCategories.contains(group.id) ? "Following" : "Follow all", systemImage: model.followedCategories.contains(group.id) ? "star.fill" : "star")
                                    .font(.subheadline.weight(.semibold))
                            }.buttonStyle(.borderless).disabled(model.saving || model.loading)
                            .accessibilityLabel(model.followedCategories.contains(group.id) ? "Unfollow all \(group.name)" : "Follow all \(group.name)")
                        }
                    }
                }
                if directoryStale {
                    Section { CacheNotice(path: "/v1/directory") }
                }
                if let count = directory?.skippedEntries, count > 0 {
                    Section { Text("\(count) entries unavailable. Pull to retry.").font(.caption).foregroundStyle(.orange) }
                }
                if let failure {
                    Section {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                    }
                }
                if let group {
                    if !group.pinned.isEmpty {
                        Section("Leader & caucus committees") {
                            ForEach(group.pinned) { entry in directoryRow(entry) }
                        }
                    }
                    Section {
                        ForEach(members) { entry in directoryRow(entry) }
                    } header: { Text(groupID == "executive-branch" ? "Statewide officials & candidates" : "Members & candidates") }

                } else if loading { ProgressView("Loading committees…") }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .civicSurface().navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About this committee list")
                }
            }
            .sheet(isPresented: $showInfo) {
                NavigationStack {
                    List {
                        Section("Data freshness") { CacheNotice(path: "/v1/directory") }
                        Section("Following") { Text("Follow all includes the listed committees, leaders and caucus funds. Membership updates apply automatically.") }
                        Section("Cash estimates") { Text("Highest estimates appear first; unavailable estimates appear last. Leaders and caucus funds stay pinned. Balances may use different quarter-end dates and exclude unreported spending. Pull to refresh.") }
                        Section("Directory") { Text("During the general election, lists should include ballot candidates and exclude primary losers and retiring incumbents. After officials are sworn in in January, lists should show sitting officeholders. After petition filing closes, add candidates who filed. Filing petitions does not guarantee ballot access. Roster changes are reviewed against official records.") }
                        Section { ProblemButton(context: ["screen": "Committee directory", "group": groupID]) }
                    }.navigationTitle("About this list").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
                }.presentationDetents([.medium, .large])
            }
            .onAppear {
                if groupID == "executive-branch", sortOrder == "district" { sortOrder = "name" }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-cash") { sortOrder = "cash" }
                #endif
            }
            .task { if directory == nil { await load() } }
            .task(id: groupID) {
                while !Task.isCancelled {
                    await loadFinances()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .refreshable { await load(); await loadFinances() }
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
                        } else { Text(finances[committee.id] == nil || finances[committee.id]?.status == "loading" ? "Calculating estimate…" : "Estimate unavailable").font(.caption).foregroundStyle(.secondary) }
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
    private var pending: Bool { finance == nil || finance?.status == "loading" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Estimated balance before unreported spending").font(.subheadline.weight(.medium))
            if let estimate = finance?.estimatedCash {
                Text(ReportContribution.currency(estimate))
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                    .foregroundStyle(CivicTheme.summaryNumber)
                    .minimumScaleFactor(0.7).lineLimit(1)
                    .accessibilityLabel("Estimated cash on hand \(ReportContribution.currency(estimate))")
            } else {
                Text(pending ? "Calculating…" : "Estimate unavailable")
                    .font(.title2.bold()).foregroundStyle(CivicTheme.summaryNumber)
            }
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            if finance?.stale == true { Text("Saved balance · Latest refresh failed").font(.caption.bold()).foregroundStyle(.yellow) }
            amount("Cash + investments", finance?.cashAndInvestments)
            amount("Monetary A-1 receipts", finance?.monetaryReceipts)
            amount("In-kind support · excluded", finance?.inKindTotal)
            if let date = finance?.asOf {
                Text("Quarter ended \(date)").font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            Text("Estimate does not subtract spending.").font(.caption).foregroundStyle(.white.opacity(0.85))
            DisclosureGroup("Calculation details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(finance?.message ?? "Loading official financial reports…")
                    Text("Adds monetary A-1 receipts to reported cash and investments. In-kind support is excluded. Unreported receipts and spending are unknown. Possible duplicate or ambiguous amended A-1s require review instead of producing a misleading estimate.")
                }.font(.caption).padding(.top, 6)
            }.font(.caption).tint(.white)
        }
        .foregroundStyle(.white).padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CivicTheme.summary, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
    private func amount(_ label: String, _ value: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(.subheadline); Spacer(minLength: 8)
                Text(value.map { ReportContribution.currency($0) } ?? (pending ? "Loading…" : "Unavailable"))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline)
                Text(value.map { ReportContribution.currency($0) } ?? (pending ? "Loading…" : "Unavailable"))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
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
            Section {
                if !member.isEmpty { Text(member).font(.subheadline.weight(.medium)).foregroundStyle(accent) }
                Text(committee.name).font(.title2.bold()).foregroundStyle(CivicTheme.ink)
                NavigationLink("Add to a private list") { AddCommitteeToList(committee: committee) }
                CacheNotice(path: "/v1/committees/\(committee.id)/history")
                Button {
                    Task { await model.toggle(committee) }
                } label: {
                    Label(model.follows(committee) ? "Following committee" : "Follow committee", systemImage: model.follows(committee) ? "star.fill" : "star")
                }.disabled(model.saving || model.loading)
            }
            Section {
                CommitteeFinanceCard(finance: finance)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
            Section {
                if let officialURL { Link("Open official committee page", destination: officialURL) }
                ProblemButton(context: ["screen": "Committee", "committee": committee.name, "committee_id": committee.id, "source_url": officialURL?.absoluteString ?? ""])
            }
        }
        .civicSurface().navigationTitle("Committee")
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

private struct QuarterlyReportView: View {
    let filing: Filing
    let report: ReportContents
    private func value(_ key: String) -> String {
        report.summary?[key].map { ReportContribution.currency($0) } ?? "Unavailable"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let period = report.period { Text(period).font(.subheadline).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 14) {
                Text("Quarter-end cash + investments").font(.subheadline)
                Text(value("cash_and_investments")).font(.largeTitle.bold()).monospacedDigit()
                    .foregroundStyle(CivicTheme.summaryNumber).minimumScaleFactor(0.7).lineLimit(1)
                Divider().overlay(.white.opacity(0.2))
                metric("Ending cash", "ending_cash")
                metric("Investments", "investments")
            }.padding(20).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CivicTheme.summary, in: RoundedRectangle(cornerRadius: 18))
            VStack(spacing: 12) {
                metric("Beginning cash", "beginning_cash")
                metric("Total receipts", "receipts")
                metric("Total expenditures", "expenditures")
                metric("In-kind contributions", "in_kind")
                metric("Debts and obligations", "debts")
            }.padding(18).background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            ForEach(["receipts", "expenditures", "in_kind", "debts", "investments"], id: \.self) { group in
                let sections = (report.sections ?? []).filter { $0.group == group }
                if !sections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.replacingOccurrences(of: "_", with: " ").capitalized).font(.title3.bold())
                        ForEach(sections) { section in
                            if section.hasDetails {
                                NavigationLink {
                                    QuarterlyScheduleView(filing: filing, section: section)
                                } label: {
                                    HStack(spacing: 12) {
                                        scheduleLabel(section)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(accent)
                                    }.padding(16)
                                        .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            } else {
                                scheduleLabel(section).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            Text("Tap an itemized category to read its entries. Unitemized amounts have no individual entries in this report. Source: Illinois State Board of Elections.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ label: String, _ key: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(label); Spacer(minLength: 12); Text(value(key)).bold().monospacedDigit() }
            VStack(alignment: .leading, spacing: 4) { Text(label); Text(value(key)).bold().monospacedDigit() }
        }.font(.subheadline)
    }
    private func scheduleLabel(_ section: QuarterlySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.headline).foregroundStyle(CivicTheme.ink)
            Text("Itemized: " + ReportContribution.currency(section.itemized)).font(.subheadline).foregroundStyle(accent)
            if section.group != "investments" {
                Text("Unitemized: " + ReportContribution.currency(section.unitemized)).font(.caption).foregroundStyle(.secondary)
            }
            if !section.hasDetails && Decimal(string: section.itemized) != Decimal(0) {
                Text("The official report does not link itemized entries.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuarterlyScheduleView: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    let section: QuarterlySection
    @State private var schedule: ItemizedSchedule?
    @State private var loading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var attempt = 0
    @AppStorage("quarterlyItemSort") private var sortOrder = "name"
    private var entries: [ScheduleEntry] {
        (schedule?.entries ?? []).filter {
            query.isEmpty || $0.fields.contains { $0.value.localizedCaseInsensitiveContains(query) }
        }.sorted { left, right in
            if sortOrder == "amount" {
                let a = amount(left), b = amount(right)
                if a != b {
                    if let a, let b { return a > b }
                    return a != nil
                }
            }
            let comparison = name(left).localizedStandardCompare(name(right))
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id < right.id
        }
    }
    private func name(_ entry: ScheduleEntry) -> String {
        let labels = ["contributor", "recipient", "payee", "name", "vendor"]
        return entry.fields.first { field in labels.contains { field.label.lowercased().contains($0) } }?.value
            ?? entry.fields.first?.value ?? ""
    }
    private func amount(_ entry: ScheduleEntry) -> Decimal? {
        guard let value = entry.fields.first(where: {
            $0.label.caseInsensitiveCompare("Amount") == .orderedSame ||
            $0.label.caseInsensitiveCompare("Current Value") == .orderedSame
        })?.value.components(separatedBy: "\n").first else { return nil }
        let cleaned = value.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "-").replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
    var body: some View {
        List {
            Section {
                Text(filing.committeeName).font(.headline)
                if let period = schedule?.period { Text(period).font(.caption).foregroundStyle(.secondary) }
                Text("Itemized total: " + ReportContribution.currency(section.itemized)).font(.subheadline.bold()).foregroundStyle(accent)
            }
            if loading { ProgressView("Loading itemized entries…") }
            else if let schedule, schedule.status == "ready" {
                Section {
                    Picker("Sort by", selection: $sortOrder) {
                        Text("Name (A–Z)").tag("name")
                        Text("Amount (highest first)").tag("amount")
                    }
                }
                Section("\(entries.count) of \(schedule.total ?? 0) entries") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(entry.fields.indices, id: \.self) { index in
                                let field = entry.fields[index]
                                if !field.value.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                                        Text(field.value).font(index == 0 ? .headline : .subheadline).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                }
                if entries.isEmpty { Text("No matching entries.").foregroundStyle(.secondary) }
            } else {
                Section {
                    Text(failure ?? schedule?.message ?? "Itemized entries unavailable.").foregroundStyle(.secondary)
                    Button("Try again") { attempt += 1 }
                }
            }
            Section {
                CacheNotice(path: "/v1/filings/\(filing.seq)/schedules/\(section.id)")
                Link("Export itemized CSV", destination: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq).csv?section=\(section.id)")!)
            }
            if let text = section.sourceUrl, let url = URL(string: text) {
                Section { Link("Open official itemized schedule", destination: url) }
            }
        }.civicSurface().navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search names, descriptions, amounts")
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-amount") { sortOrder = "amount" }
                #endif
            }
            .task(id: attempt) {
                loading = true; failure = nil
                do {
                    try await model.setup()
                    schedule = try await model.connection().call("/v1/filings/\(filing.seq)/schedules/\(section.id)")
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
                loading = false
            }
    }
}

#if DEBUG
private struct QuarterlySchedulePreview: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    @State private var section: QuarterlySection?
    var body: some View {
        Group {
            if let section { QuarterlyScheduleView(filing: filing, section: section) }
            else { ProgressView("Loading preview…") }
        }.task {
            try? await model.setup()
            let report: ReportContents? = try? await model.connection().call("/v1/filings/\(filing.seq)/contents")
            section = report?.sections?.first { $0.id == "expenditures" }
        }
    }
}
#endif

private struct CacheNotice: View {
    let path: String
    @State private var updated = Date()
    var body: some View {
        let _ = updated
        let checked = UserDefaults.standard.double(forKey: "checked:" + path)
        let stale = UserDefaults.standard.bool(forKey: "stale:" + path)
        Group {
            if checked > 0 {
                Text((stale ? "Saved data · Last verified " : "Last checked ") + Date(timeIntervalSince1970: checked).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(stale ? Color.orange : Color.secondary)
            }
        }.onReceive(NotificationCenter.default.publisher(for: Notification.Name("reportCacheChanged"))) { _ in updated = Date() }
    }
}

private struct AlertOptionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var options = AlertPreferences()
    @State private var ready = false
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Which filings?") {
                Picker("Notify me about", selection: $options.mode) {
                    Text("Every filing").tag("all")
                    Text("Quarterly reports only").tag("quarterly")
                    Text("A-1 contributions above an amount").tag("amount")
                }
                if options.mode == "amount" {
                    TextField("Minimum contribution ($)", text: $options.minimum).keyboardType(.decimalPad)
                    Text("Applies to each contribution, including separately identified in-kind support. Alerts wait until report amounts can be verified.").font(.caption)
                }
            }
            Section("Delivery") {
                Picker("Send alerts", selection: $options.delivery) {
                    Text("As reports arrive").tag("instant")
                    Text("Morning digest · 8 AM").tag("morning")
                    Text("Evening digest · 6 PM").tag("evening")
                }
                Toggle("Quiet hours", isOn: $options.quiet)
                if options.quiet {
                    Picker("Start", selection: $options.quietStart) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Picker("End", selection: $options.quietEnd) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                }
                Text("Times use \(options.timezone). Reports are grouped by committee in Notification Center. Quiet-hour alerts wait until the next allowed time.").font(.caption)
            }
            Section {
                Text("Applies to followed committees, groups, and committees in private lists. Newly following something does not send alerts for older filings.").font(.footnote)
                if !model.pushConfigured { Text("Preferences can be saved now. Phone delivery requires Apple push setup.").foregroundStyle(.secondary) }
                Button(saving ? "Saving…" : "Save alert preferences") { Task { await save() } }.disabled(!ready || saving)
                if let message { Text(message).font(.footnote) }
            }
        }.civicSurface().navigationTitle("Alert preferences").navigationBarTitleDisplayMode(.inline)
            .task {
                do { try await model.setup(); options = try await model.connection().call("/v1/me/alert-preferences"); ready = true }
                catch { message = error.localizedDescription }
            }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            let _: OK = try await model.connection().call("/v1/me/alert-preferences", method: "PUT", body: encoder.encode(options))
            message = "Preferences saved."
        } catch { message = error.localizedDescription }
    }
}

private struct MyListsView: View {
    @EnvironmentObject var model: AppModel
    @State private var lists: [ObserverList] = []
    @State private var name = ""
    @State private var failure: String?
    @State private var saving = false
    var body: some View {
        List {
            Section("Create a private list") {
                TextField("For example, Lake County races", text: $name)
                Button("Create list") { Task { await create() } }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let failure { Section { Text(failure); Button("Try again") { Task { await load() } } } }
            Section("Your lists") {
                ForEach(lists) { list in
                    NavigationLink { ObserverListView(list: list) } label: {
                        VStack(alignment: .leading) {
                            Text(list.name).font(.headline)
                            Text("\(list.committees.count) committees · \(list.newCount) new reports").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { offsets in Task { for i in offsets { await remove(lists[i]) }; await load() } }
                if lists.isEmpty { Text("Organize committees into your own lists. List members are included in filing alerts when enabled.").foregroundStyle(.secondary) }
            }
        }.civicSurface().navigationTitle("My lists").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { try await model.setup(); let response: ObserverLists = try await model.connection().call("/v1/me/lists"); lists = response.lists; failure = nil }
        catch { failure = error.localizedDescription }
    }
    private func create() async {
        saving = true; defer { saving = false }
        do { let _: CreatedList = try await model.connection().call("/v1/me/lists", method: "POST", body: JSONSerialization.data(withJSONObject: ["name": name])); name = ""; await load() }
        catch { failure = error.localizedDescription }
    }
    private func remove(_ list: ObserverList) async {
        do { let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)", method: "DELETE") }
        catch { failure = error.localizedDescription }
    }
}

private struct ObserverListView: View {
    @EnvironmentObject var model: AppModel
    let list: ObserverList
    @State private var filings: [Filing] = []
    @State private var cursor: Int?
    @State private var failure: String?
    @State private var editing = false
    @State private var seen: Int?
    @State private var currentName = ""
    var body: some View {
        List {
            Section {
                Button("Edit name and committees") { editing = true }
                Text("\(filings.filter { $0.seq > (seen ?? list.seenSeq) }.count) loaded reports since your last visit").font(.caption)
                Button("Mark these reports as seen") { Task {
                    do { let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)/seen", method: "POST", body: JSONSerialization.data(withJSONObject: ["seq": filings.map(\.seq).max() ?? list.seenSeq])); seen = filings.map(\.seq).max() ?? list.seenSeq }
                    catch { failure = error.localizedDescription }
                } }
            }
            if let failure { Text(failure); Button("Try again") { Task { await load(false) } } }
            ForEach(filings) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) } }
            if cursor != nil { Button("Load earlier reports") { Task { await load(true) } } }
            if filings.isEmpty && failure == nil { Text("No collected reports in this list yet. Add committees using Edit.").foregroundStyle(.secondary) }
        }.civicSurface().navigationTitle(currentName.isEmpty ? list.name : currentName).navigationBarTitleDisplayMode(.inline)
            .task { await load(false) }.refreshable { await load(false) }
            .sheet(isPresented: $editing, onDismiss: { Task { await load(false) } }) { NavigationStack { EditObserverListView(list: list) } }
    }
    private func load(_ more: Bool) async {
        do {
            let suffix = more ? "?before=\(cursor ?? 0)" : ""
            let page: FilingPage = try await model.connection().call("/v1/me/lists/\(list.id)/filings" + suffix)
            filings = more ? filings + page.filings : page.filings; cursor = page.nextCursor; failure = nil
            let all: ObserverLists = try await model.connection().call("/v1/me/lists")
            currentName = all.lists.first { $0.id == list.id }?.name ?? list.name
        } catch { failure = error.localizedDescription }
    }
}

private struct EditObserverListView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let list: ObserverList
    @State private var name = ""
    @State private var selected: [Committee] = []
    @State private var results: [Committee] = []
    @State private var query = ""
    @State private var failure: String?
    @State private var saving = false
    @State private var loaded = false
    var body: some View {
        List {
            Section("Name") { TextField("List name", text: $name) }
            Section("Selected committees") {
                ForEach(selected) { committee in Button { selected.removeAll { $0.id == committee.id } } label: { Label(committee.name, systemImage: "checkmark.circle.fill") } }
            }

            Section("Add committees") {
                ForEach(results.filter { c in !selected.contains(where: { $0.id == c.id }) }) { committee in
                    Button { selected.append(committee) } label: { Label(committee.name, systemImage: "plus.circle") }
                }
            }
            if let failure { Text(failure) }
        }.navigationTitle("Edit list").searchable(text: $query, prompt: "Search committees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!loaded || saving || name.isEmpty) }
            }
            .task {
                do {
                    let all: ObserverLists = try await model.connection().call("/v1/me/lists")
                    if let current = all.lists.first(where: { $0.id == list.id }) {
                        name = current.name; selected = current.committees; loaded = true
                    }
                } catch { failure = error.localizedDescription }
            }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    var parts = URLComponents(); parts.path = "/v1/committees"; parts.queryItems = [URLQueryItem(name: "q", value: query)]
                    let response: CommitteePage = try await model.connection().call(parts.string!); results = response.committees
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)", method: "PUT", body: JSONSerialization.data(withJSONObject: ["name": name, "committees": selected.map(\.id)]))
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

private struct AddCommitteeToList: View {
    @EnvironmentObject var model: AppModel
    let committee: Committee
    @State private var lists: [ObserverList] = []
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            Section { Text(committee.name).font(.headline); NavigationLink("Create or manage lists") { MyListsView() } }
            ForEach(lists) { list in
                let includes = list.committees.contains { $0.id == committee.id }
                Button { Task { await toggle(list) } } label: { Label(list.name, systemImage: includes ? "checkmark.circle.fill" : "plus.circle") }.disabled(busy)
            }
            if let message { Text(message) }
        }.navigationTitle("Add to a list").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { try await model.setup(); let page: ObserverLists = try await model.connection().call("/v1/me/lists"); lists = page.lists }
        catch { message = error.localizedDescription }
    }
    private func toggle(_ list: ObserverList) async {
        busy = true; defer { busy = false }
        var keys = list.committees.map(\.id)
        if keys.contains(committee.id) { keys.removeAll { $0 == committee.id } } else { keys.append(committee.id) }
        do { let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)", method: "PUT", body: JSONSerialization.data(withJSONObject: ["committees": keys])); await load() }
        catch { message = error.localizedDescription }
    }
}

private struct FilingByIDView: View {
    @EnvironmentObject var model: AppModel
    let seq: Int
    @State private var filing: Filing?
    @State private var failure: String?
    var body: some View {
        Group { if let filing { FilingDetail(filing: filing) } else if let failure { Text(failure) } else { ProgressView("Loading filing…") } }
            .task { do { filing = try await model.connection().call("/v1/filings/\(seq)") } catch { failure = error.localizedDescription } }
    }
}

private struct AlertInboxView: View {
    @EnvironmentObject var model: AppModel
    @State private var rows: [Filing] = []
    @State private var cursor: Int?
    @State private var failure: String?
    var body: some View {
        List {
            ForEach(rows) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) } }
            if cursor != nil { Button("Earlier alerts") { Task { await load(true) } } }
            if rows.isEmpty { Text("Delivered alerts and digest reports appear here. Push setup and notification permission are required.") }
            if let failure { Text(failure) }
        }.navigationTitle("Alerts & digests").task { await load(false) }.refreshable { await load(false) }
    }
    private func load(_ more: Bool) async {
        do {
            try await model.setup()
            let page: FilingPage = try await model.connection().call("/v1/me/alerts" + (more ? "?before=\(cursor ?? 0)" : ""))
            rows = more ? rows + page.filings : page.filings; cursor = page.nextCursor; failure = nil
        } catch { failure = error.localizedDescription }
    }
}

private struct ProblemButton: View {
    let context: [String: String]
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label("Report a problem", systemImage: "exclamationmark.bubble") }
            .sheet(isPresented: $presented) { NavigationStack { ProblemForm(context: context) } }
    }
}
private struct ProblemForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let context: [String: String]
    @State private var category = "Incorrect data"
    @State private var message = ""
    @State private var sending = false
    @State private var receipt: String?
    @State private var failure: String?
    var body: some View {
        Form {
            if let receipt {
                Section { Label("Report received", systemImage: "checkmark.circle"); Text("Reference: " + receipt).textSelection(.enabled); Text("Saved for review. Thank you for helping improve the app.").font(.subheadline) }
            } else {
                Section { Picker("Problem", selection: $category) { ForEach(["Incorrect data", "Missing report", "App issue", "Other"], id: \.self) { Text($0) } } }
                Section("What went wrong?") { TextEditor(text: $message).frame(minHeight: 140).accessibilityLabel("Describe the problem") }
                Section { Text("This sends your description, the relevant report or committee identifiers, and the app version to the app publisher. Please do not include sensitive personal information.").font(.caption) }
                if let failure { Text(failure).foregroundStyle(.red) }
                Button(sending ? "Sending…" : "Send report") { Task { await send() } }.disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || message.count > 4000)
            }
        }.civicSurface().navigationTitle("Report a problem").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(receipt == nil ? "Cancel" : "Done") { dismiss() }.disabled(sending) } }
    }
    private func send() async {
        sending = true; defer { sending = false }
        do {
            try await model.setup()
            var details = context
            details["app_version"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let result: ProblemReceipt = try await model.connection().call("/v1/me/problems", method: "POST", body: JSONSerialization.data(withJSONObject: ["category": category, "message": message, "context": details]))
            receipt = result.id; failure = nil
        } catch { failure = error.localizedDescription }
    }
}

private struct PreviewTextScale: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-large") { content.dynamicTypeSize(.accessibility2) } else { content }
        #else
        content
        #endif
    }
}
