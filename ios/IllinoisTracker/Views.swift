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
        List {
            Section { FilingRow(filing: filing) }
            Section {
                Button { Task { await model.toggle(committee) } } label: {
                    Label(model.follows(committee) ? "Unfollow committee" : "Follow committee", systemImage: model.follows(committee) ? "star.fill" : "star")
                }.disabled(model.saving || model.loading)
                if let url = filing.reportURL { Link(destination: url) { Label("Open official report", systemImage: "arrow.up.right.square") } }
                else { Text("The state did not supply a report link.").foregroundStyle(.secondary) }
            } footer: { Text("Following applies to all report types filed by this committee. Alerts begin with newly discovered filings after you follow and enable notifications.") }
        }.navigationTitle("Filing").navigationBarTitleDisplayMode(.inline)
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
