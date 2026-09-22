import SwiftUI

private let accent = Color(red: 0.12, green: 0.46, blue: 0.62)
struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView {
            FeedView().tabItem { Label("Filings", systemImage: "doc.text") }
            DiscoverView().tabItem { Label("Discover", systemImage: "magnifyingglass") }
            WatchlistView().tabItem { Label("Watchlist", systemImage: "star") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
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
struct FilingRow: View {
    let filing: Filing
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(filing.reportType.uppercased()).font(.caption.weight(.bold)).foregroundStyle(accent)
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
                    } header: { Text("Follow a group") } footer: { Text("Legislative groups will include sitting members and current-cycle candidates. Caucus committees will also be available. Groups open for following once their membership is verified.") }
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
                } header: { Text("Committees") } footer: { Text("Currently includes committees observed in the monitored feed. The complete statewide directory is still being added.") }
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
