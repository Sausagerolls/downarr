import SwiftUI

struct SonarrLibraryView: View {
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var config: ConfigStore

    @State private var showList = false
    @State private var showAdd = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        PageScaffold(title: "Series",
                     subtitle: subtitle,
                     error: sonarr.libraryState.errorMessage,
                     onRetry: { Task { await sonarr.loadAll(force: true) } }) {
            HStack(spacing: 8) {
                LibraryToolbar(filter: $sonarr.filter,
                               sortKey: $sonarr.sortKey,
                               ascending: $sonarr.sortAscending,
                               showList: $showList)
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    Task { await sonarr.loadAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload library")
            }
        } content: {
            Group {
                if sonarr.libraryState.isLoading && sonarr.series.isEmpty {
                    LoadingOverlay(text: "Loading series…")
                } else if sonarr.series.isEmpty {
                    EmptyStateView(icon: "tv",
                                   title: "No series",
                                   message: "Sonarr returned an empty library.",
                                   actionLabel: "Add a series") { showAdd = true }
                } else if showList {
                    listBody
                } else {
                    gridBody
                }
            }
        }
        .searchable(text: $sonarr.searchText, placement: .toolbar, prompt: "Search series")
        .navigationDestination(for: SonarrSeries.self) { series in
            SonarrSeriesDetailView(seriesID: series.id ?? 0)
        }
        .sheet(isPresented: $showAdd) {
            SonarrAddSeriesView()
        }
        .task { await sonarr.loadAll() }
    }

    private var subtitle: String {
        let shown = sonarr.filteredSeries.count
        return "\(shown) of \(sonarr.series.count) · \(Fmt.bytes(sonarr.totalSize)) · \(sonarr.missingEpisodeCount) episodes missing"
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(sonarr.filteredSeries) { series in
                    NavigationLink(value: series) {
                        PosterCard(title: series.title,
                                   subtitle: subtitleFor(series),
                                   imageURL: sonarr.posterURL(series),
                                   badge: badgeFor(series),
                                   badgeTint: series.missingCount > 0 ? Theme.warning : Theme.positive,
                                   progress: series.completion,
                                   progressTint: series.completion >= 1 ? Theme.positive : Theme.sonarr,
                                   dimmed: !series.monitored,
                                   placeholderIcon: "tv")
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(series) }
                }
            }
            .padding(18)
        }
    }

    private var listBody: some View {
        Table(sonarr.filteredSeries) {
            TableColumn("Title") { series in
                HStack(spacing: 8) {
                    RemoteImage(url: sonarr.posterURL(series), systemPlaceholder: "tv")
                        .frame(width: 22, height: 33)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    NavigationLink(value: series) {
                        Text(series.title).lineLimit(1)
                    }
                    .buttonStyle(.link)
                    if !series.monitored {
                        Image(systemName: "bell.slash").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
            TableColumn("Year") { Text($0.displayYear).foregroundStyle(.secondary) }
                .width(50)
            TableColumn("Network") { Text($0.network ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                .width(110)
            TableColumn("Seasons") { Text(($0.statistics?.seasonCount ?? 0).formatted()) }
                .width(60)
            TableColumn("Episodes") { series in
                Text("\(series.statistics?.episodeFileCount ?? 0)/\(series.statistics?.episodeCount ?? 0)")
                    .foregroundStyle(series.missingCount > 0 ? Theme.warning : .secondary)
            }
            .width(80)
            TableColumn("Size") { Text(Fmt.bytes($0.sizeOnDisk)).foregroundStyle(.secondary) }
                .width(80)
            TableColumn("Profile") { Text(sonarr.profileName($0.qualityProfileId)).foregroundStyle(.secondary) }
                .width(110)
            TableColumn("Status") { series in
                Pill(text: series.status?.capitalized ?? "—",
                     tint: series.isContinuing ? Theme.sonarr : .secondary)
            }
            .width(90)
        }
        .tableStyle(.inset)
    }

    private func subtitleFor(_ series: SonarrSeries) -> String {
        let seasons = series.statistics?.seasonCount ?? 0
        return "\(series.displayYear) · \(seasons) season\(seasons == 1 ? "" : "s")"
    }

    private func badgeFor(_ series: SonarrSeries) -> String? {
        if series.missingCount > 0 { return "\(series.missingCount)" }
        return nil
    }

    @ViewBuilder
    private func contextMenu(_ series: SonarrSeries) -> some View {
        if let id = series.id {
            Button(series.monitored ? "Stop monitoring" : "Start monitoring") {
                Task { await sonarr.setMonitored(seriesID: id, monitored: !series.monitored) }
            }
            Button("Search for missing episodes") {
                Task { await sonarr.search(seriesID: id) }
            }
            Button("Refresh metadata") {
                Task { await sonarr.refresh(seriesID: id) }
            }
            Button("Rescan files") {
                Task { await sonarr.rescan(seriesID: id) }
            }
            Divider()
            if let path = series.path {
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        }
    }
}
