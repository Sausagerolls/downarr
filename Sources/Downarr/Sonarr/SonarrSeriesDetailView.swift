import SwiftUI

struct SonarrSeriesDetailView: View {
    let seriesID: Int

    @EnvironmentObject private var sonarr: SonarrStore
    @State private var expandedSeasons: Set<Int> = []
    @State private var searchTarget: SearchTarget?
    @State private var showEdit = false
    @State private var showDelete = false

    private struct SearchTarget: Identifiable {
        let id = UUID()
        let title: String
        let episodeID: Int?
        let seasonNumber: Int?
    }

    private var series: SonarrSeries? { sonarr.series(id: seriesID) }

    var body: some View {
        Group {
            if let series {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(series)
                        VStack(alignment: .leading, spacing: 18) {
                            if let overview = series.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            factsGrid(series)
                            seasonsSection(series)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else {
                LoadingOverlay(text: "Loading series…")
            }
        }
        .navigationTitle(series?.title ?? "Series")
        .task {
            await sonarr.loadAll()
            await sonarr.loadEpisodes(seriesID: seriesID)
            // Open the newest season — it is what you almost always came here for.
            if expandedSeasons.isEmpty,
               let latest = series?.seasons?.map(\.seasonNumber).filter({ $0 > 0 }).max() {
                expandedSeasons = [latest]
            }
        }
        .sheet(item: $searchTarget) { target in
            InteractiveSearchSheet(
                title: target.title,
                tint: Theme.sonarr,
                load: {
                    if let episodeID = target.episodeID {
                        return await sonarr.releases(episodeID: episodeID)
                    }
                    return await sonarr.releases(seriesID: seriesID,
                                                 seasonNumber: target.seasonNumber ?? 1)
                },
                grab: { await sonarr.grab($0) })
        }
        .sheet(isPresented: $showEdit) {
            if let series { SonarrEditSeriesSheet(series: series) }
        }
        .alert("Remove \(series?.title ?? "series")?", isPresented: $showDelete) {
            Button("Remove, keep files") {
                Task { await sonarr.deleteSeries(id: seriesID, deleteFiles: false, addExclusion: false) }
            }
            Button("Remove and delete files", role: .destructive) {
                Task { await sonarr.deleteSeries(id: seriesID, deleteFiles: true, addExclusion: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing keeps the downloaded episodes on disk unless you choose to delete them.")
        }
    }

    // MARK: Header

    private func header(_ series: SonarrSeries) -> some View {
        DetailHeader(backdropURL: sonarr.fanartURL(series),
                     posterURL: sonarr.posterURL(series),
                     tint: Theme.sonarr) {
            VStack(alignment: .leading, spacing: 8) {
                Text(series.title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Pill(text: series.status?.capitalized ?? "—",
                         tint: series.isContinuing ? Theme.sonarr : .white, filled: true)
                    Pill(text: series.displayYear, tint: .white)
                    if let network = series.network { Pill(text: network, tint: .white) }
                    if let rating = series.ratings?.value, rating > 0 {
                        Pill(text: String(format: "★ %.1f", rating), tint: Theme.radarr, filled: true)
                    }
                    if let cert = series.certification { Pill(text: cert, tint: .white) }
                    Pill(text: Fmt.minutes(series.runtime), tint: .white, icon: "clock")
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await sonarr.search(seriesID: seriesID) }
                    } label: {
                        Label("Search all", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sonarr)

                    Button {
                        Task { await sonarr.setMonitored(seriesID: seriesID, monitored: !series.monitored) }
                    } label: {
                        Label(series.monitored ? "Monitored" : "Unmonitored",
                              systemImage: series.monitored ? "bell.fill" : "bell.slash")
                    }

                    Menu {
                        Button("Refresh metadata") { Task { await sonarr.refresh(seriesID: seriesID) } }
                        Button("Rescan files") { Task { await sonarr.rescan(seriesID: seriesID) } }
                        Button("Rename files") { Task { await sonarr.rename(seriesID: seriesID) } }
                        Divider()
                        Button("Edit…") { showEdit = true }
                        Button("Remove from Sonarr…", role: .destructive) { showDelete = true }
                        if let path = series.path {
                            Divider()
                            Button("Copy path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .controlSize(.small)
            }
        }
    }

    private func factsGrid(_ series: SonarrSeries) -> some View {
        let stats = series.statistics
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            StatTile(title: "On disk",
                     value: Fmt.bytes(series.sizeOnDisk),
                     subtitle: "\(stats?.episodeFileCount ?? 0) files",
                     icon: "internaldrive", tint: Theme.sonarr)
            StatTile(title: "Episodes",
                     value: "\(stats?.episodeFileCount ?? 0)/\(stats?.episodeCount ?? 0)",
                     subtitle: series.missingCount > 0 ? "\(series.missingCount) missing" : "complete",
                     icon: "checklist",
                     tint: series.missingCount > 0 ? Theme.warning : Theme.positive)
            StatTile(title: "Quality profile",
                     value: sonarr.profileName(series.qualityProfileId),
                     subtitle: series.seriesType?.capitalized,
                     icon: "slider.horizontal.3", tint: .accentColor)
            StatTile(title: series.nextAiring != nil ? "Next episode" : "Last aired",
                     value: Fmt.date(series.nextAiring ?? series.previousAiring),
                     subtitle: series.airTime,
                     icon: "calendar", tint: .accentColor)
        }
    }

    // MARK: Seasons

    private func seasonsSection(_ series: SonarrSeries) -> some View {
        let episodes = sonarr.episodes(seriesID: seriesID)
        let grouped = Dictionary(grouping: episodes, by: \.seasonNumber)
        let seasons = (series.seasons ?? []).sorted { $0.seasonNumber > $1.seasonNumber }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Seasons", subtitle: series.path)
                Spacer()
                Button("Expand all") { expandedSeasons = Set(seasons.map(\.seasonNumber)) }
                    .buttonStyle(.link).font(.caption)
                Button("Collapse") { expandedSeasons = [] }
                    .buttonStyle(.link).font(.caption)
            }
            ForEach(seasons) { season in
                SeasonPanel(
                    seriesID: seriesID,
                    season: season,
                    episodes: (grouped[season.seasonNumber] ?? []).sorted { $0.episodeNumber < $1.episodeNumber },
                    isExpanded: expandedSeasons.contains(season.seasonNumber),
                    toggle: {
                        if expandedSeasons.contains(season.seasonNumber) {
                            expandedSeasons.remove(season.seasonNumber)
                        } else {
                            expandedSeasons.insert(season.seasonNumber)
                        }
                    },
                    onManualSearch: { episode in
                        searchTarget = SearchTarget(
                            title: episode == nil
                                ? "\(series.title) — \(season.title)"
                                : "\(series.title) — \(episode!.code)",
                            episodeID: episode?.id,
                            seasonNumber: season.seasonNumber)
                    })
            }
        }
    }
}

private struct SeasonPanel: View {
    let seriesID: Int
    let season: SonarrSeason
    let episodes: [SonarrEpisode]
    let isExpanded: Bool
    let toggle: () -> Void
    let onManualSearch: (SonarrEpisode?) -> Void

    @EnvironmentObject private var sonarr: SonarrStore

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Button {
                        Task {
                            await sonarr.setSeasonMonitored(seriesID: seriesID,
                                                            seasonNumber: season.seasonNumber,
                                                            monitored: !(season.monitored ?? false))
                        }
                    } label: {
                        Image(systemName: (season.monitored ?? false) ? "bell.fill" : "bell.slash")
                            .font(.system(size: 10))
                            .foregroundStyle((season.monitored ?? false) ? Theme.sonarr : Color.secondary.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help((season.monitored ?? false) ? "Monitored" : "Not monitored")

                    Text(season.title).font(.system(size: 13, weight: .medium))

                    if let stats = season.statistics {
                        Text("\(stats.episodeFileCount ?? 0)/\(stats.episodeCount ?? 0)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        ProgressBarView(value: Double(stats.episodeFileCount ?? 0) / Double(max(1, stats.episodeCount ?? 1)),
                                        tint: (stats.percentOfEpisodes ?? 0) >= 100 ? Theme.positive : Theme.sonarr,
                                        height: 4)
                            .frame(width: 90)
                        Text(Fmt.bytes(stats.sizeOnDisk))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task { await sonarr.searchSeason(seriesID: seriesID, seasonNumber: season.seasonNumber) }
                    } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Automatic search for this season")
                    Button {
                        onManualSearch(nil)
                    } label: {
                        Image(systemName: "person.fill.viewfinder").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Manual search for this season")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                if episodes.isEmpty {
                    Text("No episodes recorded for this season.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(episodes) { episode in
                            EpisodeRow(seriesID: seriesID, episode: episode,
                                       onManualSearch: { onManualSearch(episode) })
                            if episode.id != episodes.last?.id { Divider().padding(.leading, 12) }
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct EpisodeRow: View {
    let seriesID: Int
    let episode: SonarrEpisode
    let onManualSearch: () -> Void

    @EnvironmentObject private var sonarr: SonarrStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await sonarr.setEpisodeMonitored(seriesID: seriesID,
                                                     episodeIDs: [episode.id],
                                                     monitored: !(episode.monitored ?? false))
                }
            } label: {
                Image(systemName: (episode.monitored ?? false) ? "bell.fill" : "bell.slash")
                    .font(.system(size: 9))
                    .foregroundStyle((episode.monitored ?? false) ? Theme.sonarr : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)

            Text(episode.code)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(episode.title ?? "TBA")
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                if let finale = episode.finaleType {
                    Text(finale.capitalized + " finale")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.radarr)
                }
            }

            Spacer(minLength: 8)

            if let file = episode.episodeFile {
                Pill(text: file.quality?.name ?? "File", tint: Theme.positive)
                Text(Fmt.bytes(file.size))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 62, alignment: .trailing)
            } else if episode.isMissing {
                Pill(text: "Missing", tint: Theme.warning)
            } else if !episode.hasAired {
                Text(Fmt.date(episode.airDateUtc))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Pill(text: "Not monitored", tint: .secondary)
            }

            HStack(spacing: 2) {
                Button {
                    Task { await sonarr.searchEpisodes([episode.id]) }
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("Automatic search")
                Button(action: onManualSearch) {
                    Image(systemName: "person.fill.viewfinder").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("Manual search")
                if let file = episode.episodeFile {
                    Button {
                        Task { await sonarr.deleteEpisodeFile(id: file.id, seriesID: seriesID) }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                    .help("Delete file")
                }
            }
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }
}

// MARK: - Edit sheet

struct SonarrEditSeriesSheet: View {
    let series: SonarrSeries

    @EnvironmentObject private var sonarr: SonarrStore
    @Environment(\.dismiss) private var dismiss

    @State private var monitored: Bool
    @State private var seasonFolder: Bool
    @State private var profileID: Int
    @State private var seriesType: String
    @State private var path: String

    init(series: SonarrSeries) {
        self.series = series
        _monitored = State(initialValue: series.monitored)
        _seasonFolder = State(initialValue: series.seasonFolder ?? true)
        _profileID = State(initialValue: series.qualityProfileId ?? 1)
        _seriesType = State(initialValue: series.seriesType ?? "standard")
        _path = State(initialValue: series.path ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit \(series.title)").font(.headline).padding(16)
            Divider()
            Form {
                Toggle("Monitored", isOn: $monitored)
                Toggle("Use season folders", isOn: $seasonFolder)
                Picker("Quality profile", selection: $profileID) {
                    ForEach(sonarr.profiles) { Text($0.name).tag($0.id) }
                }
                Picker("Series type", selection: $seriesType) {
                    Text("Standard").tag("standard")
                    Text("Daily").tag("daily")
                    Text("Anime").tag("anime")
                }
                TextField("Path", text: $path)
                    .font(.system(size: 11, design: .monospaced))
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        await sonarr.edit(seriesID: series.id ?? 0, changes: [
                            "monitored": .bool(monitored),
                            "seasonFolder": .bool(seasonFolder),
                            "qualityProfileId": .number(Double(profileID)),
                            "seriesType": .string(seriesType),
                            "path": .string(path),
                        ])
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 460)
    }
}
