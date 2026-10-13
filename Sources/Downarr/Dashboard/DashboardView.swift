import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var radarr: RadarrStore
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore

    @State private var upcoming: [SonarrEpisode] = []
    @State private var upcomingMovies: [RadarrMovie] = []
    @State private var isRefreshing = false

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    var body: some View {
        PageScaffold(title: "Dashboard", subtitle: subtitle) {
            Button {
                Task {
                    isRefreshing = true
                    await app.refreshEverything()
                    await loadCalendar()
                    isRefreshing = false
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !app.failedServices.isEmpty {
                        ErrorBanner(
                            message: "Not connected to \(app.failedServices.joined(separator: ", ")). "
                                + "macOS blocks the first requests while it grants local network access to a newly built app.",
                            retry: { Task { await app.retryFailedServices() } })
                    }
                    serviceHealthRow
                    statsGrid
                    if !nzbget.groups.isEmpty { activeDownloads }
                    if !activeTorrents.isEmpty { torrentDownloads }
                    if !problems.isEmpty { problemSection }
                    upcomingSection
                    recentlyAddedSection
                    diskSection
                }
                .padding(18)
            }
        }
        .task {
            await loadCalendar()
        }
    }

    private var subtitle: String {
        let parts = [
            "\(sonarr.series.count) series",
            "\(radarr.movies.count) movies",
            jellyfin.counts?.EpisodeCount.map { "\($0.formatted()) episodes in Jellyfin" } ?? "",
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    // MARK: Sections

    private var serviceHealthRow: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ServiceStatusCard(
                name: "Sonarr", tint: Theme.sonarr, icon: "tv",
                online: sonarr.status != nil,
                version: sonarr.status?.version,
                detail: "\(sonarr.series.count) series · \(Fmt.bytes(sonarr.totalSize))",
                warnings: sonarr.health.filter(\.isError).count,
                address: app.config.config.sonarr.displayAddress)
            ServiceStatusCard(
                name: "Radarr", tint: Theme.radarr, icon: "film",
                online: radarr.status != nil,
                version: radarr.status?.version,
                detail: "\(radarr.movies.count) movies · \(Fmt.bytes(radarr.totalSize))",
                warnings: radarr.health.filter(\.isError).count,
                address: app.config.config.radarr.displayAddress)
            ServiceStatusCard(
                name: "Jellyfin", tint: Theme.jellyfin, icon: "play.tv",
                online: jellyfin.systemInfo != nil,
                version: jellyfin.systemInfo?.Version,
                detail: jellyfin.systemInfo?.ServerName ?? "—",
                warnings: 0,
                address: app.config.config.jellyfin.displayAddress)
            ServiceStatusCard(
                name: "NZBGet", tint: Theme.nzbget, icon: "arrow.down.circle",
                online: nzbget.status != nil,
                version: nzbget.version,
                detail: nzbget.isPaused ? "Paused" : Fmt.rate(nzbget.downloadRate),
                warnings: 0,
                address: app.config.config.nzbget.displayAddress)
            ServiceStatusCard(
                name: "Deluge", tint: Theme.deluge, icon: "water.waves",
                online: deluge.stats != nil,
                version: deluge.version,
                detail: "\(deluge.torrents.count) torrents · ↓ \(Fmt.rate(deluge.downloadRate)) ↑ \(Fmt.rate(deluge.uploadRate))",
                warnings: deluge.errorCount,
                address: app.config.config.deluge.displayAddress)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(title: "Episodes on disk",
                     value: sonarr.episodeFileCount.formatted(),
                     subtitle: "\(sonarr.monitoredCount) series monitored",
                     icon: "tv.fill", tint: Theme.sonarr)
            StatTile(title: "Missing episodes",
                     value: sonarr.missingEpisodeCount.formatted(),
                     subtitle: "monitored and aired",
                     icon: "exclamationmark.triangle.fill",
                     tint: sonarr.missingEpisodeCount > 0 ? Theme.warning : Theme.positive)
            StatTile(title: "Movies on disk",
                     value: radarr.downloadedCount.formatted(),
                     subtitle: "\(radarr.missingCount) missing",
                     icon: "film.fill", tint: Theme.radarr)
            StatTile(title: "Library size",
                     value: Fmt.bytes(sonarr.totalSize + radarr.totalSize),
                     subtitle: "TV + movies on disk",
                     icon: "internaldrive.fill", tint: .accentColor)
            StatTile(title: "Queue",
                     value: (sonarr.queue.count + radarr.queue.count).formatted(),
                     subtitle: queueSubtitle,
                     icon: "tray.and.arrow.down.fill", tint: Theme.nzbget)
            StatTile(title: "Free space",
                     value: Fmt.bytes(nzbget.freeDiskBytes),
                     subtitle: "on the download disk",
                     icon: "externaldrive.fill", tint: .accentColor)
        }
    }

    private var queueSubtitle: String {
        var parts: [String] = []
        if !nzbget.groups.isEmpty { parts.append("\(nzbget.groups.count) in NZBGet") }
        if deluge.downloadingCount > 0 { parts.append("\(deluge.downloadingCount) in Deluge") }
        return parts.isEmpty ? "nothing downloading" : parts.joined(separator: " · ")
    }

    private var activeDownloads: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Downloading",
                          subtitle: nzbget.isPaused ? "NZBGet is paused" : "\(Fmt.rate(nzbget.downloadRate)) · \(nzbget.eta) remaining") {
                app.selection = .downloadQueue
            }
            VStack(spacing: 8) {
                ForEach(nzbget.groups.prefix(5)) { group in
                    HStack(spacing: 10) {
                        Image(systemName: group.isPostProcessing ? "gearshape.2.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(group.statusTint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name).font(.caption).lineLimit(1)
                            ProgressBarView(value: group.progress, tint: group.statusTint, height: 4)
                        }
                        Text("\(Int(group.progress * 100))%")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Text(Fmt.megabytes(group.RemainingSizeMB))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
            .card()
        }
    }

    /// Torrents worth showing on the dashboard: moving, or stuck with an error.
    private var activeTorrents: [DelugeTorrent] {
        deluge.torrents
            .filter { $0.isDownloading || $0.isError || $0.isActive }
            .sorted { $0.fraction > $1.fraction }
    }

    private var torrentDownloads: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Torrents",
                          subtitle: "↓ \(Fmt.rate(deluge.downloadRate)) · ↑ \(Fmt.rate(deluge.uploadRate))") {
                app.selection = .delugeTorrents
            }
            VStack(spacing: 8) {
                ForEach(activeTorrents.prefix(5)) { torrent in
                    HStack(spacing: 10) {
                        Image(systemName: torrent.statusIcon)
                            .foregroundStyle(torrent.statusTint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(torrent.title).font(.caption).lineLimit(1)
                            ProgressBarView(value: torrent.fraction, tint: torrent.statusTint, height: 4)
                        }
                        Text(String(format: "%.0f%%", torrent.progress ?? 0))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Text(torrent.etaText)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
            .card()
        }
    }

    private var problems: [(String, String, Color)] {
        var rows: [(String, String, Color)] = []
        for item in sonarr.health where item.isError {
            rows.append(("Sonarr", item.message ?? "", Theme.sonarr))
        }
        for item in radarr.health where item.isError {
            rows.append(("Radarr", item.message ?? "", Theme.radarr))
        }
        for record in sonarr.queue.compactMap({ q -> (String, String, Color)? in
            guard let problem = q.problem else { return nil }
            return ("Sonarr queue", "\(q.label): \(problem)", Theme.sonarr)
        }) { rows.append(record) }
        for record in radarr.queue.compactMap({ q -> (String, String, Color)? in
            guard let problem = q.problem else { return nil }
            return ("Radarr queue", "\(q.label): \(problem)", Theme.radarr)
        }) { rows.append(record) }
        for torrent in deluge.torrents {
            guard let problem = torrent.problem else { continue }
            rows.append(("Deluge", "\(torrent.title): \(problem)", Theme.deluge))
        }
        return rows
    }

    private var problemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Needs attention", subtitle: "\(problems.count) items")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(problems.prefix(6).enumerated()), id: \.offset) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Pill(text: row.element.0, tint: row.element.2)
                        Text(row.element.1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
                if problems.count > 6 {
                    Text("+ \(problems.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .card()
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coming up", subtitle: "Next 14 days") {
                app.selection = .calendar
            }
            if upcoming.isEmpty && upcomingMovies.isEmpty {
                Text("Nothing scheduled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(upcoming.prefix(12)) { episode in
                            UpcomingCard(
                                title: episode.series?.title ?? "Unknown",
                                subtitle: "\(episode.code) · \(episode.title ?? "")",
                                date: episode.airDateUtc,
                                imageURL: episode.series.flatMap { sonarr.posterURL($0) },
                                tint: Theme.sonarr)
                        }
                        ForEach(upcomingMovies.prefix(8)) { movie in
                            UpcomingCard(
                                title: movie.title,
                                subtitle: movie.studio ?? "Movie",
                                date: movie.availabilityDate,
                                imageURL: radarr.posterURL(movie),
                                tint: Theme.radarr)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recently added to Jellyfin",
                          subtitle: jellyfin.systemInfo?.ServerName) {
                app.selection = .jellyfinBrowse
            }
            if jellyfin.latest.isEmpty {
                Text(jellyfin.isAuthenticated ? "Nothing new." : "Sign in to Jellyfin from Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(jellyfin.latest.prefix(14)) { item in
                            PosterCard(title: item.Name ?? "Untitled",
                                       subtitle: item.subtitle,
                                       imageURL: jellyfin.posterURL(item),
                                       width: 104,
                                       placeholderIcon: item.kind.icon)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Storage")
            VStack(spacing: 10) {
                ForEach(mergedDisks) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(disk.path).font(.caption)
                            Spacer()
                            Text("\(Fmt.bytes(disk.freeSpace)) free of \(Fmt.bytes(disk.totalSpace))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ProgressBarView(value: disk.usedFraction,
                                        tint: disk.usedFraction > 0.9 ? Theme.danger : .accentColor,
                                        height: 5)
                    }
                }
            }
            .card()
        }
    }

    private var mergedDisks: [ArrDiskSpace] {
        var seen = Set<String>()
        return (sonarr.diskSpace + radarr.diskSpace).filter { seen.insert($0.path).inserted }
    }

    private func loadCalendar() async {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        upcoming = await sonarr.calendar(start: start, end: end)
        upcomingMovies = await radarr.calendar(start: start, end: end)
    }
}

private struct ServiceStatusCard: View {
    let name: String
    let tint: Color
    let icon: String
    let online: Bool
    let version: String?
    let detail: String
    let warnings: Int
    let address: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle()
                    .fill(online ? Theme.positive : Theme.danger)
                    .frame(width: 7, height: 7)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let version { Pill(text: "v\(version)", tint: tint) }
                if warnings > 0 { Pill(text: "\(warnings) health", tint: Theme.danger) }
                Spacer()
                Link(destination: URL(string: address) ?? URL(string: "http://localhost")!) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                }
                .help("Open \(name) in the browser")
            }
        }
        .card()
    }
}

private struct UpcomingCard: View {
    let title: String
    let subtitle: String
    let date: Date?
    let imageURL: URL?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: imageURL, systemPlaceholder: "film")
                .frame(width: 44, height: 66)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                Pill(text: relativeLabel, tint: tint)
            }
            .frame(width: 150, alignment: .leading)
        }
        .card(padding: 10, radius: 10)
    }

    private var relativeLabel: String {
        guard let date else { return "TBA" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 0 { return Fmt.timeOnly.string(from: date) }
        if days == 1 { return "Tomorrow" }
        return "in \(days) days"
    }
}
