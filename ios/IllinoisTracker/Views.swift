import SwiftUI
import PDFKit

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
    static var background: Color { pink ? adaptive(0xFFF2F6, 0xFFF2F6) : adaptive(0xF7F6F1, 0x0B1C27) }
    static var surface: Color { pink ? adaptive(0xFFFFFF, 0xFFFFFF) : adaptive(0xFFFFFF, 0x142D3A) }
    static var ink: Color { pink ? adaptive(0x482237, 0x482237) : adaptive(0x092C44, 0xF7F5EE) }
    static var secondary: Color { pink ? adaptive(0x785466, 0x785466) : adaptive(0x536675, 0xB4C8D1) }
    static var accent: Color { pink ? adaptive(0x96375F, 0x96375F) : adaptive(0x007B89, 0x83DEE4) }
    static var summary: Color { pink ? adaptive(0x662740, 0x662740) : adaptive(0x092C44, 0x123443) }
    static var summaryNumber: Color { pink ? .white : adaptive(0xFFFFFF, 0x9FE8EE) }
}
private var accent: Color { CivicTheme.accent }


private struct TactileButtonStyle: ButtonStyle {
    var inset: CGFloat = 10
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.red : CivicTheme.ink)
            .padding(inset)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CivicTheme.surface)
                    .shadow(color: .black.opacity(enabled && !configuration.isPressed ? 0.10 : 0.02),
                            radius: configuration.isPressed ? 0 : 2, x: 0, y: configuration.isPressed ? 0 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LinearGradient(colors: [CivicTheme.accent.opacity(0.22), CivicTheme.accent.opacity(0.10)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
private struct TactileRowSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(CivicTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(CivicTheme.accent.opacity(0.23), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 2, x: 0, y: 2)
            .padding(.vertical, 3)
    }
}
private struct TactileDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

private extension View {
    func civicSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .background(CivicTheme.background)
            .foregroundStyle(CivicTheme.ink)
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .contentMargins(.top, 8, for: .scrollContent)
            .toolbarBackground(CivicTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .environment(\.defaultMinListRowHeight, 44)
            .modifier(PreviewTextScale())
            .buttonStyle(TactileButtonStyle())
            .disclosureGroupStyle(TactileDisclosureStyle())
    }
}
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab = 0
    @AppStorage("appearance") private var appearance = "light"
    private var preferredScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-night") || ProcessInfo.processInfo.arguments.contains("--preview-launch") { return .dark }
        #endif
        return appearance == "system" ? nil : (appearance == "dark" ? .dark : .light)
    }
    var body: some View {
        Group {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-launch") {
            LaunchScreenPreview().ignoresSafeArea()
        } else if ProcessInfo.processInfo.arguments.contains("--preview-about") {
            NavigationStack { BrandAboutView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
            SettingsView()
        } else if ProcessInfo.processInfo.arguments.contains("--preview-inkind") {
            NavigationStack { InKindSourcePreview() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-add-list") {
            NavigationStack { AddCommitteeToList(committee: Committee(id: "1b5ce79b8d1251adaf13eda719fd6d7a", name: "Daniel Didech Campaign Committee")) }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-pdf") {
            NavigationStack { FilingByIDView(seq: 2001000) }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-problem") {
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
            .onAppear { BrandAppearance.configure() }
            .onChange(of: appearance) { _, _ in BrandAppearance.configure() }
            .fontDesign(.default)
            .modifier(PreviewTextScale())
            .buttonStyle(TactileButtonStyle())
            .disclosureGroupStyle(TactileDisclosureStyle())
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
                        HotRacesView().tabItem { Label("Hot Races", systemImage: "flame") }.tag(3)
            TopPACsView().tabItem { Label("Top PACs", systemImage: "chart.bar.xaxis") }.tag(4)
            AlertsView().tabItem { Label("Alerts", systemImage: "bell") }.tag(2)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-reports") { selectedTab = 1 }
            if ProcessInfo.processInfo.arguments.contains("--preview-alerts") { selectedTab = 2 }
            if ProcessInfo.processInfo.arguments.contains("--preview-hot-races") { selectedTab = 3 }
            if ProcessInfo.processInfo.arguments.contains("--preview-top-pacs") { selectedTab = 4 }
            #endif
        }
        .tint(accent)
        .toolbarBackground(CivicTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
                VStack(spacing: 12) {
                    ForEach(HomeCaucus.allCases) { caucus in
                        NavigationLink(value: caucus) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if caucus == .executive { Text(caucus.title).font(.system(.title2, design: .default, weight: .bold)).fixedSize(horizontal: false, vertical: true) }
                                    else {
                                    Text(caucus.chamber)
                                        .font(.system(.title, design: .default, weight: .bold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(caucus.party)
                                        .font(.system(.title, design: .default, weight: .bold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 38, height: 38)
                                    .background(.white.opacity(0.16), in: Circle())
                            }
                            .foregroundStyle(caucus.foreground)
                            .padding(.horizontal, 22).padding(.vertical, caucus == .executive ? 17 : 16)
                            .frame(maxWidth: .infinity, minHeight: caucus == .executive ? 76 : 110, alignment: .leading)
                            .background {
                                ZStack(alignment: .trailing) {
                                    LinearGradient(colors: caucus.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Circle().stroke(.white.opacity(0.09), lineWidth: 1)
                                        .frame(width: 210, height: 210).offset(x: 65, y: -35)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: caucus.colors.last!.opacity(0.20), radius: 5, x: 0, y: 3)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(caucus.title)
                            .accessibilityHint("Opens the committee list")
                        }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle(inset: 0))
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(CivicTheme.background)
            .navigationTitle("Checks & Balances")
            .toolbar { AppUtilities() }
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
            BrandList {
                Section {
                    if model.monitor?.stale == true { Label("Feed delayed · showing saved reports", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if (model.monitor?.unresolvedGaps ?? 0) > 0 { Text("A possible gap in filing history is under review.").font(.caption).foregroundStyle(.orange) }
                    Picker("Filings", selection: $watchOnly) {
                        Text("All filings").tag(false); Text("My alerts").tag(true)
                    }.pickerStyle(.segmented)
                }
                Section {
                    let rows = watchOnly ? model.watched : model.filings
                    if model.loading && rows.isEmpty { ProgressView("Loading filings…") }
                    else if rows.isEmpty {
                        ContentUnavailableView(watchOnly ? "Choose your alerts" : "No filings loaded", systemImage: watchOnly ? "bell" : "doc.text", description: Text(watchOnly ? "Choose committees, categories, or custom lists in Alerts to see their reports here." : "Pull down to try again."))
                    }
                    ForEach(rows) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle()) }
                    if watchOnly ? model.watchedHasMore : model.allHasMore {
                        Button { Task { await model.loadMore(watchlist: watchOnly) } } label: { HStack { Spacer(); Text(model.loading ? "Loading…" : "Load earlier filings"); Spacer() } }.disabled(model.loading)
                    }
                }
            }
            .listSectionSpacing(.compact).contentMargins(.top, 0, for: .scrollContent)
            .civicSurface().navigationTitle("Latest Reports").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .toolbar { AppUtilities(); if model.loading { ToolbarItem { ProgressView() } } }
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
        case .other: return CivicTheme.secondary
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
    var linkCommittee = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportTypeBadge(reportType: filing.reportType)
            if linkCommittee {
                NavigationLink {
                    CommitteeFilingsView(committee: Committee(id: filing.committeeKey, name: filing.committeeName), member: "", officialURL: nil)
                } label: {
                    HStack {
                        Text(filing.committeeName).font(.headline).foregroundStyle(CivicTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(accent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle()).accessibilityHint("Opens this committee’s reports and financial overview")
            } else {
                Text(filing.committeeName).font(.headline).foregroundStyle(CivicTheme.ink)
            }
            if showPreview, let p = filing.preview {
                if p.kind == "a1" {
                    if let total = p.total { Text(ReportContribution.currency(total)).font(.title3.bold()).monospacedDigit().foregroundStyle(accent) }
                    if let names = p.contributors { Text(names.joined(separator: " • ") + ((p.contributorCount ?? 0) > names.count ? " + \((p.contributorCount ?? 0) - names.count) more" : "")).font(.subheadline).foregroundStyle(.primary) }
                    Text("\(p.contributionCount ?? 0) contribution\(p.contributionCount == 1 ? "" : "s")" + (p.includesInKind == true ? " · includes in-kind" : "")).font(.caption).foregroundStyle(CivicTheme.secondary)
                } else if p.kind == "quarterly" {
                    if let period = p.period { Text(period).font(.subheadline).foregroundStyle(CivicTheme.secondary) }
                    previewMetric("Starting balance · cash", p.beginningCash)
                    previewMetric("Receipts", p.receipts)
                    previewMetric("Spending", p.expenditures)
                    Divider()
                    previewMetric("Ending balance", p.cashAndInvestments)
                    Text("Cash on hand + investments")
                        .font(.caption).foregroundStyle(CivicTheme.secondary)
                }
            } else if showPreview && (FilingReportKind(filing.reportType) == .a1 || FilingReportKind(filing.reportType) == .quarterly) {
                Text(filing.previewStatus == "unavailable" ? "Summary temporarily unavailable" : "Loading summary…").font(.caption).foregroundStyle(CivicTheme.secondary)
            }
            if !filing.displayDate.isEmpty { Text(filing.displayDate).font(.caption).foregroundStyle(CivicTheme.secondary) }
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
                FilingRow(filing: filing, showPreview: false, linkCommittee: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))

                Group {
                if filing.reportURL?.path.lowercased().contains("cdpdfviewer.aspx") == true || filing.reportType.localizedCaseInsensitiveContains("correspondence") || filing.reportType.localizedCaseInsensitiveContains("letter") {
                    InlineFilingPDF(filing: filing)
                } else { NativeReportContents(filing: filing) }
                }.id(filing.seq)
                CacheNotice(path: "/v1/filings/\(filing.seq)/contents")
                ShareLink("Share report", item: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq)")!)
                Link("Export report CSV", destination: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq).csv")!)
                CommitteeListLink(committee: committee)

                VStack(spacing: 0) {
                    CommitteeAlertButton(committee: committee, explain: true).padding(18)
                    if let url = filing.reportURL {
                        Divider().padding(.leading, 18)
                        Link(destination: url) {
                            Label("Open official report", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        }
                    }
                }.background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                ProblemButton(context: ["screen": "Filing", "committee": filing.committeeName, "committee_id": filing.committeeKey, "filing_id": String(filing.seq), "source_url": filing.url ?? ""])
                Text("Committee and custom-list selections apply to new reports. Report-type filters and phone delivery are managed in Alerts.")
                    .font(.footnote).foregroundStyle(CivicTheme.secondary)
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
            Text("Report details").font(.headline)
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
                        .font(.caption).foregroundStyle(CivicTheme.secondary)
                }
                ForEach(contributions) { contribution in
                    ContributionCard(contribution: contribution)
                }
                Text("Source: Illinois State Board of Elections")
                    .font(.caption).foregroundStyle(CivicTheme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Report details unavailable", systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text(failure ?? report?.message ?? "Open the official report below to read this filing.")
                        .font(.subheadline).foregroundStyle(CivicTheme.secondary)
                    if report?.status != "unsupported" {
                        Button("Try again") { attempt += 1 }.buttonStyle(TactileButtonStyle())
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
                Text("from").font(.subheadline).foregroundStyle(CivicTheme.secondary)
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
            Text(label).font(.caption).foregroundStyle(CivicTheme.secondary)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}

struct AlertsView: View {
    var body: some View { NavigationStack { AlertCenterView() } }
}

private struct AlertCenterView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        BrandList {
            Section {
                HStack {
                    Label(model.alertsEnabled && model.pushConfigured && model.notificationStatus == "Allowed on this iPhone" ? "Notifications on" : "Notifications paused", systemImage: "bell.badge")
                        .font(.headline)
                    Spacer()
                }
                if model.alertsEnabled {
                    Button("Pause notifications") { Task { await model.disableAlerts() } }
                } else {
                    Button("Turn on notifications") { Task { await model.enableAlerts() } }
                        .disabled(!model.pushConfigured)
                }
                if !model.pushConfigured {
                    Text("Choose your alerts now. Phone notifications will be available once Apple push setup is complete.")
                        .font(.caption).foregroundStyle(CivicTheme.secondary)
                } else if model.notificationStatus == "Disabled in iPhone Settings", let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Allow notifications in iPhone Settings", destination: url)
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.allReports }, set: { value in Task { await model.setAllReports(value) } })) {
                    Label("All reports", systemImage: "globe.americas")
                }.disabled(model.saving || model.loading)
                Text(model.allReports ? "Every committee in the statewide filing feed. Your selections below are saved if you turn this off." : "Or choose the groups and committees you want below.")
                    .font(.caption).foregroundStyle(CivicTheme.secondary)
            } header: { Text("What do you want to follow?") }
            Section {
                NavigationLink { CaucusAlertsView() } label: {
                    sourceLabel("Caucuses & categories", subtitle: "\(model.followedCategories.count) selected", icon: "person.3")
                }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                NavigationLink { CommitteeSearchView(manageAlerts: true) } label: {
                    sourceLabel("Individual committees", subtitle: "\(model.following.count) selected", icon: "person.crop.square")
                }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                NavigationLink { MyListsView() } label: {
                    sourceLabel("Custom lists", subtitle: "Group committees for races or topics you follow", icon: "list.bullet.rectangle")
                }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
            } footer: {
                Text("Selections save automatically. New reports only. Overlapping selections produce one alert per report.")
            }
            Section {
                NavigationLink { AlertOptionsView() } label: { Label("Report types & delivery", systemImage: "slider.horizontal.3") }
                    .listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                NavigationLink { AlertInboxView() } label: { Label("Alert history", systemImage: "clock.arrow.circlepath") }
                    .listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
            }
        }.civicSurface().navigationTitle("Alerts").navigationBarTitleDisplayMode(.inline).toolbar { AppUtilities() }
            .task { await model.refreshPermission(); await model.refreshIfNeeded() }
            .refreshable { await model.refresh() }
    }
    private func sourceLabel(_ title: String, subtitle: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(CivicTheme.secondary)
            }
        } icon: { Image(systemName: icon).foregroundStyle(accent) }
        .padding(.vertical, 6)
    }
}

private struct CaucusAlertsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        BrandList {
            Section {
                ForEach(model.categories) { category in
                    Toggle(isOn: Binding(get: { model.followedCategories.contains(category.id) }, set: { _ in Task { await model.toggleCategory(category.id) } })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name).font(.headline)
                            Text(category.verified == 1 ? "\(category.memberCount) committees" : "Committee list under review")
                                .font(.caption).foregroundStyle(CivicTheme.secondary)
                        }
                    }.disabled(category.verified != 1 || model.saving || model.loading)
                }
            } footer: {
                Text("Includes listed candidates, leaders, and caucus committees. Membership changes apply automatically.")
            }
            if model.allReports { Section { Text("All reports is on, so these committees are already covered. These selections are saved for later.").font(.caption) } }
        }.civicSurface().navigationTitle("Caucuses & categories").navigationBarTitleDisplayMode(.inline)
    }
}

struct DiscoverView: View {
    var body: some View { NavigationStack { CommitteeSearchView(manageAlerts: false) } }
}

private struct CommitteeSearchView: View {
    @EnvironmentObject var model: AppModel
    var manageAlerts: Bool
    @State private var query = ""
    @State private var rows: [Committee] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = 0
    private var showingSelected: Bool { manageAlerts && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        BrandList {
            if showingSelected {
                Section {
                    ForEach(model.following) { committee in committeeRow(committee) }
                    if model.following.isEmpty {
                        ContentUnavailableView("Choose a committee", systemImage: "bell.badge", description: Text("Search by committee name above, then tap Add committee alert."))
                    }
                } header: { Text("Your committee alerts") }
            } else {
                Section {
                    ForEach(rows) { committee in committeeRow(committee) }
                    if loading { ProgressView("Searching…") }
                    if let failure {
                        Text(failure).foregroundStyle(CivicTheme.secondary)
                        Button("Try again") { Task { await search(more: false) } }
                    } else if rows.isEmpty && !loading {
                        ContentUnavailableView.search(text: query)
                    }
                    if cursor != nil { Button("More results") { Task { await search(more: true) } }.disabled(loading) }
                } header: { Text(query.isEmpty ? "Browse committees" : "Results") }
                Section {
                    Text("Search includes the app’s directory and committees found in the filing feed.").font(.caption).foregroundStyle(CivicTheme.secondary)
                }
            }
        }.civicSurface().navigationTitle(manageAlerts ? "Committee alerts" : "Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search committee names")
            .task(id: query) {
                generation += 1; rows = []; cursor = nil; failure = nil
                guard !showingSelected else { loading = false; return }
                loading = true
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await search(more: false) }
                catch { }
            }
    }
    private func committeeRow(_ committee: Committee) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { CommitteeFilingsView(committee: committee, member: "", officialURL: nil) } label: {
                Text(committee.name).font(.headline)
            }.buttonStyle(TactileButtonStyle())
            CommitteeAlertButton(committee: committee)
        }.padding(.vertical, 5)
    }
    @MainActor private func search(more: Bool) async {
        generation += 1; let requestedGeneration = generation
        loading = true; failure = nil
        defer { if generation == requestedGeneration { loading = false } }
        var parts = URLComponents(); parts.path = "/v1/committees"
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        if more, let cursor { parts.queryItems?.append(URLQueryItem(name: "after", value: cursor)) }
        do {
            let page: CommitteePage = try await model.connection().call(parts.string ?? "/v1/committees")
            guard !Task.isCancelled, generation == requestedGeneration else { return }
            rows = more ? rows + page.committees : page.committees; cursor = page.nextCursor
        } catch { if !Task.isCancelled && generation == requestedGeneration { failure = error.localizedDescription } }
    }
}

struct SettingsView: View {
    var presented = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false
    @AppStorage("appearance") private var appearance = "light"
    var body: some View {
        NavigationStack {
            BrandList {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("Ivory · Light").tag("light")
                        Text("Midnight · Dark").tag("dark")
                        Text("Rose · Pink").tag("pink")
                        Text("Follow iPhone appearance").tag("system")
                    }
                } header: { Text("Appearance") } footer: {
                    Text("Ivory, Midnight, and Rose share the same clear layouts and readable report colors. You can also follow your iPhone’s appearance.")
                }
                Section {
                    NavigationLink { AlertCenterView() } label: { Label("Manage alerts", systemImage: "bell") }
                        .listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                }
                Section("Help") { ProblemButton(context: ["screen": "Settings"]) }
                Section {
                    NavigationLink { BrandAboutView() } label: {
                        HStack(spacing: 14) {
                            BrandIcon(size: 48)
                            VStack(alignment: .leading, spacing: 4) { Text("Checks & Balances").font(.headline); Text("About, sources & service status").font(.caption).foregroundStyle(CivicTheme.secondary) }
                        }.padding(.vertical, 4)
                    }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                }
                Section("Your data") {
                    Text("No email or password required. Your installation identifier, selected committees and categories, and push token are stored to deliver your alerts. Problem reports you submit are also stored for review. Your alert selections belong to this installation and do not sync between devices.").font(.subheadline)
                    Button("Delete my saved data", role: .destructive) { confirmDelete = true }.disabled(model.saving || model.loading)
                }
            }
            .civicSurface().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { if presented { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
            .confirmationDialog("Delete your alert selections and custom lists, and disable notifications?", isPresented: $confirmDelete, titleVisibility: .visible) {
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
            BrandList {
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
                                Label(model.followedCategories.contains(group.id) ? "Remove category alerts" : "Add category alerts", systemImage: model.followedCategories.contains(group.id) ? "bell.slash" : "bell.badge")
                                    .font(.subheadline.weight(.semibold))
                            }.buttonStyle(TactileButtonStyle()).disabled(model.saving || model.loading)
                            .accessibilityLabel(model.followedCategories.contains(group.id) ? "Remove category alerts for \(group.name)" : "Add category alerts for \(group.name)")
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
                        Text(failure).foregroundStyle(CivicTheme.secondary)
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
                    BrandList {
                        Section("Data freshness") { CacheNotice(path: "/v1/directory") }
                        Section("Category alerts") { Text("Adds new reports from the listed committees, leaders, and caucus funds to your alerts. Membership updates apply automatically.") }
                        Section("Cash estimates") { Text("Highest estimates appear first; unavailable estimates appear last. Leaders and caucus funds stay pinned. Balances may use different quarter-end dates and exclude unreported spending. Pull to refresh.") }
                        Section("Directory") { Text("During the general election, lists include ballot candidates and sitting senators whose seats are not up this cycle, excluding primary losers and retiring incumbents. After officials are sworn in in January, lists should show sitting officeholders. After petition filing closes, add candidates who filed. Filing petitions does not guarantee ballot access. Roster changes are reviewed against official records.") }
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
                        } else { Text(finances[committee.id] == nil || finances[committee.id]?.status == "loading" ? "Calculating estimate…" : "Estimate unavailable").font(.caption).foregroundStyle(CivicTheme.secondary) }
                    }
                    if let district = entry.district {
                        Text("District \(district)").font(.caption).foregroundStyle(CivicTheme.secondary)
                    } else if entry.role == "Leader" {
                        Text("Chamber leader").font(.caption).foregroundStyle(CivicTheme.secondary)
                    }
                }.padding(.vertical, 3)
            }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle())
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.member).font(.headline)
                if let district = entry.district { Text("District \(district)").font(.caption) }
                Text("Committee to be added").font(.subheadline).foregroundStyle(CivicTheme.secondary)
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
    @State private var visibleReports: Set<Int> = []
    @Environment(\.scenePhase) private var scenePhase
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
        BrandList {
            Section {
                if !member.isEmpty { Text(member).font(.subheadline.weight(.medium)).foregroundStyle(accent) }
                Text(committee.name).font(.title2.bold()).foregroundStyle(CivicTheme.ink)
                CommitteeListLink(committee: committee)
                CacheNotice(path: "/v1/committees/\(committee.id)/history")
                CommitteeAlertButton(committee: committee, explain: true)
            }
            Section {
                CommitteeFinanceCard(finance: finance)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("Reports") {
                if let history {
                    if history.status == "ready", let total = history.total {
                        Text("\(total) reports · Since \(history.creationDate ?? "committee creation")").font(.caption).foregroundStyle(CivicTheme.secondary)
                    } else { Text(history.message ?? "Loading history…").font(.caption).foregroundStyle(CivicTheme.secondary) }
                }
                if let failure {
                    Text(failure).foregroundStyle(CivicTheme.secondary)
                    Button("Try again") { Task { await load(more: false) } }
                }
                ForEach(filings) { filing in
                    NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing)
                        .onAppear { visibleReports.insert(filing.seq) }
                        .onDisappear { visibleReports.remove(filing.seq) }
                    }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle())
                }
                if loading { ProgressView("Loading reports…") }
                else if loaded && filings.isEmpty && failure == nil && history?.status == "ready" {
                    Text("No reports from this committee have been collected yet. Add a committee alert for new filings.").foregroundStyle(CivicTheme.secondary)
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
        .task(id: visibleReports.sorted().map(String.init).joined(separator: ",") + String(describing: scenePhase)) {
            guard scenePhase == .active else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await refreshVisibleSummaries()
        }
        .refreshable { await load(more: false); await refreshVisibleSummaries(singlePass: true) }
    }
    @MainActor private func refreshVisibleSummaries(singlePass: Bool = false) async {
        for _ in 0..<(singlePass ? 1 : 60) {
            guard !Task.isCancelled, scenePhase == .active else { return }
            let ids = filings.filter {
                visibleReports.contains($0.seq) && $0.preview == nil &&
                (FilingReportKind($0.reportType) == .a1 || FilingReportKind($0.reportType) == .quarterly)
            }.prefix(50).map { String($0.seq) }
            guard !ids.isEmpty else { return }
            do {
                let batch: SummaryBatch = try await model.connection().call("/v1/summary-previews?ids=" + ids.joined(separator: ","))
                try Task.checkCancellation()
                for update in batch.summaries {
                    if let index = filings.firstIndex(where: { $0.seq == update.seq }) {
                        if let preview = update.preview { filings[index].preview = preview }
                        filings[index].previewStatus = update.status
                    }
                }
                if !batch.summaries.contains(where: { $0.status == "loading" }) { return }
            } catch {
                if Task.isCancelled { return }
            }
            if singlePass { return }
            try? await Task.sleep(for: .seconds(3))
        }
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
            if let period = report.period { Text(period).font(.subheadline).foregroundStyle(CivicTheme.secondary) }
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
                                }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle(inset: 0))
                            } else {
                                scheduleLabel(section).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CivicTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            Text("Tap an itemized category to read its entries. Unitemized amounts have no individual entries in this report. Source: Illinois State Board of Elections.")
                .font(.caption).foregroundStyle(CivicTheme.secondary)
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
                Text("Unitemized: " + ReportContribution.currency(section.unitemized)).font(.caption).foregroundStyle(CivicTheme.secondary)
            }
            if !section.hasDetails && Decimal(string: section.itemized) != Decimal(0) {
                Text("The official report does not link itemized entries.").font(.caption).foregroundStyle(CivicTheme.secondary)
            }
        }
    }
}

private struct QuarterlyScheduleView: View {
    @EnvironmentObject var model: AppModel
    let filing: Filing
    let section: QuarterlySection
    var since: String? = nil
    var includedAmount: String? = nil
    @State private var schedule: ItemizedSchedule?
    @State private var loading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var attempt = 0
    @AppStorage("quarterlyItemSort") private var sortOrder = "name"
    private var entries: [ScheduleEntry] {
        (schedule?.entries ?? []).filter { entry in
            if let since, let date = receiptDate(entry), date < since { return false }
            return query.isEmpty || entry.fields.contains { $0.value.localizedCaseInsensitiveContains(query) }
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
    private func receiptDate(_ entry: ScheduleEntry) -> String? {
        let dateField = entry.fields.first { ["date", "date received", "received date", "receipt date"].contains($0.label.lowercased()) }?.value
        let amountLines = entry.fields.first { $0.label.lowercased() == "amount" }?.value.components(separatedBy: "\n") ?? []
        guard let raw = dateField ?? (amountLines.count == 2 ? amountLines[1] : nil) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yyyy"
        guard let date = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
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
        BrandList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                Text(filing.committeeName).font(.headline)
                if let period = schedule?.period { Text(period).font(.caption).foregroundStyle(CivicTheme.secondary) }
                Text((includedAmount == nil ? "Itemized total: " : "Included in post-primary total: ") + ReportContribution.currency(includedAmount ?? section.itemized)).font(.subheadline.bold()).foregroundStyle(accent)
                if since != nil {
                    Text("In-kind receipts from March 18, 2026 onward. Any entry without a readable date is retained for review.").font(.caption).foregroundStyle(CivicTheme.secondary)
                    if section.unitemized != "0.00" { Text("This report also discloses " + ReportContribution.currency(section.unitemized) + " in unitemized support without individual receipt details. Only quarters entirely after the primary include that amount in the total.").font(.caption).foregroundStyle(CivicTheme.secondary) }
                }
                }.padding(.vertical, 4)
            }
            if loading { ProgressView("Loading itemized entries…") }
            else if let schedule, schedule.status == "ready" {
                Section {
                    Picker("Sort by", selection: $sortOrder) {
                        Text("Name (A–Z)").tag("name")
                        Text("Amount (highest first)").tag("amount")
                    }
                }
                Section(since == nil ? "\(entries.count) of \(schedule.total ?? 0) entries" : "\(entries.count) matching entries") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(entry.fields.indices, id: \.self) { index in
                                let field = entry.fields[index]
                                if !field.value.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(field.label).font(.caption).foregroundStyle(CivicTheme.secondary)
                                        Text(field.value).font(index == 0 ? .headline : .subheadline).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                }
                if entries.isEmpty { Text("No matching entries.").foregroundStyle(CivicTheme.secondary) }
            } else {
                Section {
                    Text(failure ?? schedule?.message ?? "Itemized entries unavailable.").foregroundStyle(CivicTheme.secondary)
                    Button("Try again") { attempt += 1 }
                }
            }
            Section {
                CacheNotice(path: "/v1/filings/\(filing.seq)/schedules/\(section.id)")
                Link(since == nil ? "Export itemized CSV" : "Export full schedule CSV", destination: URL(string: "https://illinois-filing-tracker.onrender.com/share/filing/\(filing.seq).csv?section=\(section.id)")!)
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
                    .font(.caption).foregroundStyle(stale ? Color.orange : CivicTheme.secondary)
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
        BrandForm {
            Section("Which filings?") {
                Picker("Notify me about", selection: $options.mode) {
                    Text("All report types").tag("all")
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
                Text("Applies to your selected alert sources, including All reports when enabled. Only newly discovered filings trigger notifications.").font(.footnote)
                if !model.pushConfigured { Text("Preferences can be saved now. Phone delivery requires Apple push setup.").foregroundStyle(CivicTheme.secondary) }
                Button(saving ? "Saving…" : "Save alert preferences") { Task { await save() } }.disabled(!ready || saving)
                if let message { Text(message).font(.footnote) }
            }
        }.civicSurface().navigationTitle("Report types & delivery").navigationBarTitleDisplayMode(.inline)
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
    @State private var editingList: ObserverList?
    @State private var failure: String?
    @State private var saving = false
    var body: some View {
        BrandList {
            Section("Create a custom list") {
                TextField("For example, Lake County races", text: $name)
                Button("Create list & choose committees") { Task { await create() } }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let failure { Section { Text(failure); Button("Try again") { Task { await load() } } } }
            Section("Your lists") {
                ForEach(lists) { list in
                    NavigationLink { ObserverListView(list: list) } label: {
                        VStack(alignment: .leading) {
                            Text(list.name).font(.headline)
                            Text("\(list.committees.count) committees · \(list.newCount) new reports").font(.caption).foregroundStyle(CivicTheme.secondary)
                        }
                    }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle())
                }.onDelete { offsets in Task { for i in offsets { await remove(lists[i]) }; await load() } }
                if lists.isEmpty { Text("Create a list, then choose its committees. Their new reports are included in your alerts. Only you can see your lists.").foregroundStyle(CivicTheme.secondary) }
            }
        }.civicSurface().navigationTitle("Custom lists").task { await load() }.refreshable { await load() }
            .sheet(item: $editingList, onDismiss: { Task { await load() } }) { list in NavigationStack { EditObserverListView(list: list) } }
    }
    private func load() async {
        do { try await model.setup(); let response: ObserverLists = try await model.connection().call("/v1/me/lists"); lists = response.lists; failure = nil }
        catch { failure = error.localizedDescription }
    }
    private func create() async {
        saving = true; defer { saving = false }
        do { let created: CreatedList = try await model.connection().call("/v1/me/lists", method: "POST", body: JSONSerialization.data(withJSONObject: ["name": name])); name = ""; await load(); editingList = lists.first { $0.id == created.id } }
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
        BrandList {
            Section {
                Button("Manage committees & list name") { editing = true }
                Text("\(filings.filter { $0.seq > (seen ?? list.seenSeq) }.count) loaded reports since your last visit").font(.caption)
                Button("Mark these reports as seen") { Task {
                    do { let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)/seen", method: "POST", body: JSONSerialization.data(withJSONObject: ["seq": filings.map(\.seq).max() ?? list.seenSeq])); seen = filings.map(\.seq).max() ?? list.seenSeq }
                    catch { failure = error.localizedDescription }
                } }
            }
            if let failure { Text(failure); Button("Try again") { Task { await load(false) } } }
            ForEach(filings) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle()) }
            if cursor != nil { Button("Load earlier reports") { Task { await load(true) } } }
            if filings.isEmpty && failure == nil { Text("No collected reports in this list yet. Tap Manage committees & list name to add some.").foregroundStyle(CivicTheme.secondary) }
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
        BrandList {
            Section("Name") { TextField("List name", text: $name); Text("Listed committees are included in your alerts. Changes take effect when you tap Save list.").font(.caption).foregroundStyle(CivicTheme.secondary) }
            Section("Selected committees") {
                ForEach(selected) { committee in Button { selected.removeAll { $0.id == committee.id } } label: { VStack(alignment: .leading) { Text(committee.name); Label("Remove from list", systemImage: "minus.circle").font(.caption) } } }
            }

            Section("Add committees") {
                ForEach(results.filter { c in !selected.contains(where: { $0.id == c.id }) }) { committee in
                    Button { selected.append(committee) } label: { VStack(alignment: .leading) { Text(committee.name); Label("Add to list", systemImage: "text.badge.plus").font(.caption) } }
                }
            }
            if let failure { Text(failure) }
        }.navigationTitle("Edit list").searchable(text: $query, prompt: "Search committees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save list") { Task { await save() } }.disabled(!loaded || saving || name.isEmpty) }
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

private struct CommitteeAlertButton: View {
    @EnvironmentObject var model: AppModel
    let committee: Committee
    var explain = false
    @State private var busy = false
    @State private var confirmation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task {
                    busy = true
                    let previouslySelected = model.follows(committee)
                    await model.toggle(committee)
                    if model.follows(committee) != previouslySelected {
                        confirmation = previouslySelected ? "Individual alert removed. Category and custom-list alerts are unchanged." : "Committee alert added. Delivery follows your settings in Alerts."
                    }
                    busy = false
                }
            } label: {
                Label(busy ? "Saving…" : (model.follows(committee) ? "Remove committee alert" : "Add committee alert"),
                      systemImage: model.follows(committee) ? "bell.slash" : "bell.badge")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(TactileButtonStyle()).disabled(busy || model.saving || model.loading)
            if let confirmation {
                Text(confirmation).font(.caption).foregroundStyle(CivicTheme.secondary).accessibilityAddTraits(.updatesFrequently)
            } else if explain {
                Text(model.follows(committee) ? "Individual committee alert selected." : "Add new reports from this committee to your alerts.")
                    .font(.caption).foregroundStyle(CivicTheme.secondary)
            }
            if explain && (!model.alertsEnabled || !model.pushConfigured) {
                Text("Phone notifications are paused. Manage delivery in Alerts.").font(.caption).foregroundStyle(CivicTheme.secondary)
            }
        }
    }
}
private struct CommitteeListLink: View {
    let committee: Committee
    var body: some View {
        NavigationLink { AddCommitteeToList(committee: committee) } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add to a custom list")
                    Text("Choose a list, or create one with this committee.").font(.caption).foregroundStyle(CivicTheme.secondary)
                }
            } icon: { Image(systemName: "text.badge.plus") }
            .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(TactileButtonStyle())
            .listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
    }
}

private struct AddCommitteeToList: View {
    @EnvironmentObject var model: AppModel
    let committee: Committee
    @State private var lists: [ObserverList] = []
    @State private var name = ""
    @State private var message: String?
    @State private var failure: String?
    @State private var busy = false
    @State private var loading = true
    var body: some View {
        BrandList {
            Section {
                Text(committee.name).font(.headline)
                Text("Custom lists include their committees’ new reports in your alerts. Only you can see your lists.")
                    .font(.caption).foregroundStyle(CivicTheme.secondary)
                if let message { Label(message, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(accent) }
            }
            Section("Choose an existing list") {
                if loading { ProgressView("Loading your lists…") }
                ForEach(lists) { list in
                    let included = list.committees.contains { $0.id == committee.id }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(list.name).font(.headline)
                        if included { Label("Committee is in this list", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(accent) }
                        Button { Task { await setMembership(list, included: !included) } } label: {
                            Label(included ? "Remove from this list" : "Add to this list", systemImage: included ? "minus.circle" : "text.badge.plus")
                        }.buttonStyle(TactileButtonStyle()).disabled(busy || loading)
                    }.padding(.vertical, 4)
                }
                if !loading && lists.isEmpty && failure == nil { Text("No custom lists yet. Create one below.").foregroundStyle(CivicTheme.secondary) }
            }
            Section {
                TextField("List name, e.g. Lake County races", text: $name)
                Button { Task { await createAndAdd() } } label: { Label("Create list & add committee", systemImage: "plus.rectangle.on.folder") }
                    .disabled(busy || loading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
            } header: { Text("Create a new custom list") } footer: { Text("Creates the list with this committee already included.") }
            if let failure { Section { Text(failure).foregroundStyle(CivicTheme.secondary); Button("Reload lists") { Task { await load() } }.disabled(busy) } }
        }.civicSurface().navigationTitle("Add to a custom list").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async {
        loading = true; defer { loading = false }
        do { try await model.setup(); let page: ObserverLists = try await model.connection().call("/v1/me/lists"); lists = page.lists; failure = nil }
        catch { failure = error.localizedDescription }
    }
    @MainActor private func setMembership(_ list: ObserverList, included: Bool) async {
        busy = true; defer { busy = false }; failure = nil; message = nil
        do {
            let _: OK = try await model.connection().call("/v1/me/lists/\(list.id)/committees/\(committee.id)", method: "PUT", body: JSONSerialization.data(withJSONObject: ["included": included]))
            message = included ? "Added to \(list.name). Reports are included in your alert selections." : "Removed from \(list.name). Other alert selections are unchanged."
            await load(); try? await model.refreshWatched()
        } catch { failure = error.localizedDescription }
    }
    @MainActor private func createAndAdd() async {
        busy = true; defer { busy = false }; failure = nil; message = nil
        let listName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: CreatedList = try await model.connection().call("/v1/me/lists", method: "POST", body: JSONSerialization.data(withJSONObject: ["name": listName, "committees": [committee.id]]))
            name = ""; message = "Created \(listName) with this committee. Reports are included in your alert selections."
            await load(); try? await model.refreshWatched()
        } catch { failure = error.localizedDescription }
    }
}

private struct FilingByIDView: View {
    @EnvironmentObject var model: AppModel
    let seq: Int
    @State private var filing: Filing?
    @State private var failure: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if let filing { FilingDetail(filing: filing) }
            else if let failure { ContentUnavailableView { Label("Report unavailable", systemImage: "doc.text") } description: { Text(failure) } actions: { Button("Try again") { attempt += 1 } } }
            else { ProgressView("Loading filing…") }
        }.task(id: attempt) {
            failure = nil
            do { filing = try await model.connection().call("/v1/filings/\(seq)") }
            catch { if !Task.isCancelled { failure = "The report could not be loaded. Please try again." } }
        }
    }
}

private struct AlertInboxView: View {
    @EnvironmentObject var model: AppModel
    @State private var rows: [Filing] = []
    @State private var cursor: Int?
    @State private var failure: String?
    var body: some View {
        BrandList {
            ForEach(rows) { filing in NavigationLink { FilingDetail(filing: filing) } label: { FilingRow(filing: filing) }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden).buttonStyle(TactileButtonStyle()) }
            if cursor != nil { Button("Earlier alerts") { Task { await load(true) } } }
            if rows.isEmpty { Text("Delivered alerts and digest reports appear here. Push setup and notification permission are required.") }
            if let failure { Text(failure) }
        }.civicSurface().navigationTitle("Alert history").navigationBarTitleDisplayMode(.inline).task { await load(false) }.refreshable { await load(false) }
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
        BrandForm {
            if let receipt {
                Section { Label("Report received", systemImage: "checkmark.circle"); Text("Reference: " + receipt).textSelection(.enabled); Text("Saved for review. Thank you for helping improve Checks & Balances.").font(.subheadline) }
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

private struct NativePDFView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        view.autoScales = true
        view.maxScaleFactor = 6
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document; view.autoScales = true }
    }
}
private struct InlineFilingPDF: View {
    let filing: Filing
    @State private var document: PDFDocument?
    @State private var failure: String?
    @State private var attempt = 0
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let document {
                HStack {
                    Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")").font(.caption).foregroundStyle(CivicTheme.secondary)
                    Spacer()
                    Button { expanded = true } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                NativePDFView(document: document).frame(height: 560).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Scroll to read • Pinch to zoom").font(.caption).foregroundStyle(CivicTheme.secondary)
            } else if let failure {
                Text(failure).font(.subheadline)
                Button("Try again") { attempt += 1 }
            } else { ProgressView("Loading PDF…").frame(maxWidth: .infinity, minHeight: 160) }
        }
        .task(id: attempt) { await load() }
        .fullScreenCover(isPresented: $expanded) {
            NavigationStack {
                if let document { NativePDFView(document: document).navigationTitle("Official document").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } } } }
            }
        }
    }
    private func load() async {
        failure = nil
        guard filing.reportURL != nil else { failure = "The state has not linked a document for this filing."; return }
        do {
            let url = URL(string: "https://illinois-filing-tracker.onrender.com/v1/filings/\(filing.seq)/document.pdf")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 70))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 20_000_000, let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                throw APIError.message("The PDF could not be loaded. Retry or use Open official report below.")
            }
            try Task.checkCancellation()
            document = pdf
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}


private struct AppUtilities: ToolbarContent {
    var showBrand = true
    @State private var settings = false
    var body: some ToolbarContent {
        if showBrand {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { BrandAboutView() } label: { BrandIcon(size: 32) }
                    .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("About Checks & Balances")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink { CommitteeSearchView(manageAlerts: false) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search committees")
            Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                .sheet(isPresented: $settings) { SettingsView(presented: true) }
        }
    }
}

struct HotRacesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var page: HotRacePage?
    @State private var selectedCandidate: RaceCandidate?
    @State private var filter = "All"
    @State private var failure: String?
    @State private var about = false
    private var races: [HotRace] { (page?.races ?? []).filter { filter == "All" || $0.chamber == filter } }
    var body: some View {
        NavigationStack {
            BrandList {
                Section {
                    Picker("Chamber", selection: $filter) {
                        Text("All").tag("All"); Text("House").tag("House"); Text("Senate").tag("Senate")
                    }.pickerStyle(.segmented)
                }
                if let failure { Section { Text(failure).font(.caption); Button("Try again") { Task { await load() } } } }
                if page == nil && failure == nil { ProgressView("Loading races…") }
                ForEach(races) { race in
                    Section {
                        RaceComparison(race: race, onSelect: { selectedCandidate = $0 })
                    } header: { Text(race.title).font(.headline).foregroundStyle(CivicTheme.ink).textCase(nil) }
                }
            }.civicSurface().navigationTitle("Hot Races").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: Binding(get: { selectedCandidate != nil }, set: { if !$0 { selectedCandidate = nil } })) {
                    if let candidate = selectedCandidate, let committee = candidate.committee { CommitteeFilingsView(committee: committee, member: candidate.name, officialURL: nil) }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { about = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About Hot Races") }
                    AppUtilities(showBrand: false)
                }
                .sheet(isPresented: $about) {
                    NavigationStack { BrandList { Text(page?.note ?? "A curated watchlist of competitive Illinois legislative races."); Text("Cash and investments are reported balances. Estimates add subsequent monetary A-1 receipts and do not subtract unreported spending. Each candidate’s quarter-end date is shown. PDF-only filings are excluded from estimates; see committee calculation details.") }.navigationTitle("About Hot Races").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { about = false } } } }
                }
                .refreshable { await load() }
                .task(id: phase) {
                    guard phase == .active else { return }
                    while !Task.isCancelled { await load(); do { try await Task.sleep(for: .seconds(15)) } catch { return } }
                }
        }
    }
    @MainActor private func load() async {
        do { page = try await model.connection().call("/v1/hot-races"); failure = nil }
        catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}

private struct RaceComparison: View {
    let race: HotRace
    let onSelect: (RaceCandidate) -> Void
    @State private var supportCandidate: RaceCandidate?
    private func partyColor(_ party: String) -> Color { party == "Democratic" ? .blue : party == "Republican" ? .red : .purple }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(race.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(candidate.party).font(.caption.bold()).foregroundStyle(partyColor(candidate.party))
                        if candidate.committee != nil {
                            Button { onSelect(candidate) } label: {
                                HStack(alignment: .top, spacing: 4) { Text(candidate.name).font(.headline); Image(systemName: "chevron.right").font(.caption.bold()) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(TactileButtonStyle(inset: 8))
                        } else { Text(candidate.name).font(.headline); Text("Committee being verified").font(.caption).foregroundStyle(CivicTheme.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            comparison("Reported cash + investments", field: { $0.cashAndInvestments })
            HStack(alignment: .top, spacing: 14) {
                ForEach(race.candidates) { candidate in
                    Text(candidate.finance?.asOf.map { "As of \($0)" } ?? "Date pending")
                        .font(.caption2).foregroundStyle(CivicTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            comparison("Monetary A-1s since quarter end", field: { $0.monetaryReceipts })
            Divider()
            comparison("Estimated balance before unreported spending", field: { $0.estimatedCash }, prominent: true)
            if race.candidates.contains(where: { $0.finance?.stale == true }) { Text("A saved estimate is shown while its source is refreshed.").font(.caption).foregroundStyle(CivicTheme.secondary) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("In-kind support since primary").font(.subheadline.bold())
                Text("Received March 18, 2026 onward · Not cash").font(.caption2).foregroundStyle(CivicTheme.secondary)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(race.candidates) { candidate in
                        Button { supportCandidate = candidate } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(candidate.postPrimaryInKind?.amount.map(ReportContribution.currency) ?? (candidate.postPrimaryInKind?.status == "unavailable" ? "Unavailable" : "Calculating…"))
                                        .font(.subheadline.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption2.bold())
                                }
                                if candidate.postPrimaryInKind?.status == "partial" { Text("Partial total").font(.caption2) }
                                if candidate.postPrimaryInKind?.stale == true { Text("Update delayed").font(.caption2) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(TactileButtonStyle(inset: 8))
                         .accessibilityLabel("\(candidate.name), in-kind support since primary, \(candidate.postPrimaryInKind?.amount.map(ReportContribution.currency) ?? "calculating"), view sources and coverage")
                    }
                }
            }
            DisclosureGroup("Committee alerts") {
                ForEach(race.candidates) { candidate in
                    if let committee = candidate.committee {
                        VStack(alignment: .leading, spacing: 5) { Text(candidate.name).font(.subheadline.bold()); CommitteeAlertButton(committee: committee, explain: true) }.padding(.vertical, 5)
                    }
                }
            }.font(.subheadline)
        }.padding(.vertical, 8)
         .sheet(item: $supportCandidate) { candidate in InKindSupportDetails(candidate: candidate) }
    }
    private func comparison(_ label: String, field: @escaping (CommitteeFinance) -> String?, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(CivicTheme.secondary)
            HStack(alignment: .top, spacing: 14) {
                ForEach(race.candidates) { candidate in
                    Text(candidate.finance.flatMap(field).map(ReportContribution.currency) ?? (candidate.finance?.status == "unavailable" ? "Unavailable" : "Calculating…"))
                        .font(prominent ? .headline : .subheadline).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(prominent ? CivicTheme.accent : CivicTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).minimumScaleFactor(0.7).lineLimit(1)
                        .accessibilityLabel("\(candidate.name), \(label), \(candidate.finance.flatMap(field).map(ReportContribution.currency) ?? "unavailable")")
                }
            }
        }
    }
}

private struct InKindSupportDetails: View {
    let candidate: RaceCandidate
    @State private var selectedSource: InKindSource?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            BrandList {
                Section {
                    Text(candidate.name).font(.headline)
                    Text(candidate.postPrimaryInKind?.amount.map(ReportContribution.currency) ?? "Not yet available").font(.title.bold()).monospacedDigit()
                    Text("In-kind support received since March 18, 2026").font(.subheadline)
                    if let support = candidate.postPrimaryInKind {
                        if support.status == "partial" { Text("Partial total — see coverage below").font(.subheadline.bold()) }
                        DisclosureGroup("How this total is calculated") { Text(support.note).font(.caption).foregroundStyle(CivicTheme.secondary) }
                        if let checked = support.checkedAt { Text("Checked \(Date(timeIntervalSince1970: checked).formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                        if support.stale == true { Text("Source refresh delayed. Showing saved disclosures.").font(.caption) }
                    } else { Text("Loading the committee’s official disclosures…") }
                }
                if let support = candidate.postPrimaryInKind {
                    if !support.issues.isEmpty {
                        Section("Coverage") { ForEach(support.issues, id: \.self) { Text($0).font(.subheadline) } }
                    }
                    Section("In-kind report details") {
                        ForEach(support.sources) { source in
                            Button { selectedSource = source } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.reportType).font(.subheadline.bold())
                                        Text(source.period).font(.caption)
                                        Text("Included: \(ReportContribution.currency(source.amount))").font(.subheadline).monospacedDigit()
                                    }
                                    Spacer(); Image(systemName: "chevron.right")
                                }
                            }.buttonStyle(TactileButtonStyle(inset: 8))
                             .accessibilityHint("Read in-kind contributions within the app")
                        }
                    }
                }
            }.civicSurface().navigationTitle("In-kind support").navigationBarTitleDisplayMode(.inline)
             .navigationDestination(isPresented: Binding(get: { selectedSource != nil }, set: { if !$0 { selectedSource = nil } })) {
                 if let source = selectedSource { NativeInKindSourceView(source: source) }
             }
             .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(CivicTheme.accent)
    }
}

private struct NativeInKindSourceView: View {
    let source: InKindSource
    @EnvironmentObject var model: AppModel
    @State private var report: ReportContents?
    @State private var loading = true
    @State private var failure: String?
    @State private var attempt = 0
    private var contributions: [ReportContribution] {
        (report?.contributions ?? []).filter { entry in
            let kind = entry.contributionType.lowercased().replacingOccurrences(of: "–", with: "-")
            return (kind.contains("in-kind") || kind.contains("in kind")) && entry.receivedDate >= "2026-03-18" &&
                !(source.excludedPeriods ?? []).contains { $0.count == 2 && $0[0] <= entry.receivedDate && entry.receivedDate <= $0[1] }
        }
    }
    var body: some View {
        Group {
            if let filing = source.filing, let report, report.status == "ready", report.kind == "quarterly",
               let section = report.sections?.first(where: { $0.id == "in_kind" }), section.hasDetails {
                QuarterlyScheduleView(filing: filing, section: section, since: "2026-03-18", includedAmount: source.amount)
            } else {
                BrandList {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                        Text(source.filing?.committeeName ?? "In-kind contributions").font(.headline)
                        Text(source.period).font(.caption).foregroundStyle(CivicTheme.secondary)
                        Text("Included: " + ReportContribution.currency(source.amount)).font(.headline).foregroundStyle(CivicTheme.accent)
                        }.padding(.vertical, 4)
                    }
                    if loading { ProgressView("Loading in-kind details…") }
                    else if let report, report.status == "ready" {
                        if report.kind == "quarterly" {
                            Text("This report has no linked itemized in-kind schedule.")
                            if let section = report.sections?.first(where: { $0.id == "in_kind" }) {
                                Text("Reported itemized: " + ReportContribution.currency(section.itemized))
                                Text("Reported unitemized: " + ReportContribution.currency(section.unitemized))
                                Text("Unitemized support does not include individual contributor details.").font(.caption).foregroundStyle(CivicTheme.secondary)
                            }
                        } else {
                            Section("In-kind contributions included in this total") {
                                ForEach(contributions) { contribution in ContributionCard(contribution: contribution) }
                                if contributions.isEmpty { Text("No matching in-kind contributions in this filing.") }
                            }
                        }
                    } else {
                        Text(failure ?? report?.message ?? "Details are not yet available.")
                        Button("Try again") { attempt += 1 }.buttonStyle(TactileButtonStyle())
                    }
                    Section {
                        Text("Source: Illinois State Board of Elections").font(.caption).foregroundStyle(CivicTheme.secondary)
                        if let url = URL(string: source.url) { Link("Open official report", destination: url).buttonStyle(TactileButtonStyle()) }
                    }
                }.civicSurface().navigationTitle("In-kind details").navigationBarTitleDisplayMode(.inline)
            }
        }.task(id: attempt) {
            loading = true; failure = nil
            do {
                guard let filing = source.filing else { throw APIError.message("Refresh Hot Races to load this report’s details.") }
                try await model.setup()
                report = try await model.connection().call("/v1/filings/\(filing.seq)/contents")
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            loading = false
        }
    }
}

struct TopPACsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var page: TopPACPage?
    @State private var query = ""
    @State private var failure: String?
    @State private var about = false
    private var rows: [RankedPAC] { (page?.committees ?? []).filter { query.isEmpty || $0.committee.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            BrandList {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                    Text("Reported cash + investments").font(.subheadline.bold())
                    if let date = page?.checkedAt { Text("Updated \(Date(timeIntervalSince1970: date).formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(CivicTheme.secondary) }
                    if page?.status == "partial" { Text("Building ranking: \(page?.processed ?? 0) of \(page?.reportCount ?? 0) reports checked. Order may change.").font(.caption).foregroundStyle(CivicTheme.secondary) }
                    if page?.status == "stale" { Text("Saved ranking · Source refresh delayed").font(.caption).foregroundStyle(CivicTheme.secondary) }
                    }
                }
                if let failure { Section { Text(failure).font(.caption); Button("Try again") { Task { await load() } } } }
                if page == nil || (page?.status == "loading" && rows.isEmpty) { ProgressView("Loading PAC balances…") }
                ForEach(rows) { pac in
                    NavigationLink { CommitteeFilingsView(committee: pac.committee, member: "", officialURL: nil) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(pac.rank)").font(.title3.bold()).foregroundStyle(CivicTheme.accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pac.committee.name).font(.headline)
                                Text(ReportContribution.currency(pac.balance)).font(.title3.bold()).monospacedDigit().foregroundStyle(CivicTheme.accent)
                                Text("\(pac.committeeType) · \(pac.asOf)").font(.caption).foregroundStyle(CivicTheme.secondary)
                            }
                        }.padding(.vertical, 7)
                    }.listRowBackground(TactileRowSurface()).listRowSeparator(.hidden)
                }
                if rows.isEmpty && page?.status == "ready" { ContentUnavailableView.search(text: query) }
            }.civicSurface().navigationTitle("Top PACs").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search ranked PACs")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { about = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About PAC rankings") }
                    AppUtilities(showBrand: false)
                }
                .sheet(isPresented: $about) { NavigationStack { BrandList { Text(page?.note ?? "Ranked using official reported balances."); Text("\(page?.total ?? 0) committees with verified balances. Showing up to 100. \(page?.excluded ?? 0) active committees without a verified balance in this ranking.") }.navigationTitle("About Top PACs").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { about = false } } } } }
                .refreshable { await load() }
                .task(id: phase) {
                    guard phase == .active else { return }
                    while !Task.isCancelled { await load(); do { try await Task.sleep(for: .seconds(30)) } catch { return } }
                }
        }
    }
    @MainActor private func load() async {
        do { page = try await model.connection().call("/v1/top-pacs"); failure = nil }
        catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}

#if DEBUG
private struct InKindSourcePreview: View {
    @EnvironmentObject var model: AppModel
    @State private var source: InKindSource?
    @State private var error: String?
    var body: some View {
        Group {
            if let source { NativeInKindSourceView(source: source) }
            else if let error { Text(error) }
            else { ProgressView("Loading in-kind preview…") }
        }.task {
            do {
                try await model.setup()
                let page: HotRacePage = try await model.connection().call("/v1/hot-races")
                let kind = ProcessInfo.processInfo.arguments.contains("--preview-inkind-a1") ? "A-1" : "D-2"
                source = page.races.first?.candidates.last?.postPrimaryInKind?.sources.first { $0.reportType.hasPrefix(kind) && $0.amount != "0.00" }
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif


// One visual system for every list and form, including sheets and nested screens.
private struct BrandList<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { List { content.listRowBackground(CivicTheme.surface).listRowSeparatorTint(CivicTheme.secondary.opacity(0.16)) }.civicSurface() }
}
private struct BrandForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { Form { content.listRowBackground(CivicTheme.surface).listRowSeparatorTint(CivicTheme.secondary.opacity(0.16)) }.civicSurface() }
}
private struct BrandIcon: View {
    var size: CGFloat = 44
    var body: some View {
        Image("BrandMark").resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}
private struct BrandAboutView: View {
    var body: some View {
        BrandList {
            Section {
                Image("FullBrand").resizable().scaledToFit()
                    .padding(10).background(Color(red: 250/255, green: 248/255, blue: 242/255))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Checks & Balances. The Unofficial Authority on Illinois Campaign Finance. Illinois Capitol with eight columns and a small Lincoln statue.")
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Welcome to Checks & Balances") {
                Text("A smarter way to read Illinois campaign finance reports, track committees, and manage filing alerts.")
                Text("Not affiliated with or endorsed by the Illinois State Board of Elections or any government agency.").font(.subheadline).foregroundStyle(CivicTheme.secondary)
            }
            Section("Reports & calculations") {
                Text("Official reports are the source of record. Amendments can change previously reported amounts.")
                Text("Estimated balances combine reported cash and investments with later monetary A-1 receipts. They exclude in-kind support, unreported spending, and PDF-only filings.").font(.subheadline).foregroundStyle(CivicTheme.secondary)
                Text("The service checks for new filings every minute. State publication delays, network conditions, and phone settings can affect alert timing.").font(.subheadline).foregroundStyle(CivicTheme.secondary)
                Link(destination: URL(string: "https://www.elections.il.gov/rss/LatestReportsFiled.aspx")!) { Label("Official filing feed", systemImage: "arrow.up.right.square") }
                Link(destination: URL(string: "https://illinois-filing-tracker.onrender.com/")!) { Label("Service status", systemImage: "waveform.path.ecg") }
            }
            Section {
                ProblemButton(context: ["screen": "About Checks & Balances"])
                HStack { Text("Version"); Spacer(); Text("1.0 · Build " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")).monospacedDigit().foregroundStyle(CivicTheme.secondary) }
            }
        }.navigationTitle("Checks & Balances").navigationBarTitleDisplayMode(.inline)
    }
}
enum BrandAppearance {
    @MainActor static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(CivicTheme.background)
        nav.titleTextAttributes = [.foregroundColor: UIColor(CivicTheme.ink), .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(CivicTheme.ink), .font: UIFont.systemFont(ofSize: 32, weight: .bold)]
        nav.shadowColor = UIColor(CivicTheme.secondary.opacity(0.10))
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let tab = UITabBarAppearance(); tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(CivicTheme.background)
        tab.shadowColor = UIColor(CivicTheme.secondary.opacity(0.12))
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(CivicTheme.secondary)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(CivicTheme.secondary)]
            item.selected.iconColor = UIColor(CivicTheme.accent)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(CivicTheme.accent)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

#if DEBUG
// Renders the compiled launch storyboard for visual verification, with no launch delay.
private struct LaunchScreenPreview: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()!
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
