import SwiftUI

struct JellyfinLibrariesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jellyfin: JellyfinStore

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        PageScaffold(title: "Jellyfin libraries",
                     subtitle: subtitle,
                     error: jellyfin.connectionState.errorMessage,
                     onRetry: { Task { await jellyfin.loadOverview(force: true) } }) {
            HStack(spacing: 8) {
                Button {
                    Task { await jellyfin.scanAll() }
                } label: {
                    Label("Scan all libraries", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task { await jellyfin.loadOverview(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if !jellyfin.isAuthenticated && jellyfin.connectionState.isLoading {
                    LoadingOverlay(text: "Signing in to Jellyfin…")
                } else if jellyfin.libraries.isEmpty {
                    EmptyStateView(icon: "books.vertical",
                                   title: "No libraries",
                                   message: "Either Jellyfin has no libraries or the sign-in failed. Check Settings.",
                                   actionLabel: "Sign in again") {
                        Task {
                            await jellyfin.authenticate()
                            await jellyfin.loadOverview(force: true)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            countsRow
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Libraries",
                                              subtitle: "Scan, refresh metadata, or browse the contents")
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(jellyfin.libraries) { folder in
                                        LibraryCard(folder: folder)
                                    }
                                }
                            }
                            tasksSection
                        }
                        .padding(18)
                    }
                }
            }
        }
        .task { await jellyfin.loadOverview() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let name = jellyfin.systemInfo?.ServerName { parts.append(name) }
        if let version = jellyfin.systemInfo?.Version { parts.append("v\(version)") }
        parts.append(app.config.config.jellyfin.displayAddress)
        return parts.joined(separator: " · ")
    }

    private var countsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            StatTile(title: "Movies", value: (jellyfin.counts?.MovieCount ?? 0).formatted(),
                     icon: "film.fill", tint: Theme.jellyfin)
            StatTile(title: "Series", value: (jellyfin.counts?.SeriesCount ?? 0).formatted(),
                     icon: "tv.fill", tint: Theme.jellyfin)
            StatTile(title: "Episodes", value: (jellyfin.counts?.EpisodeCount ?? 0).formatted(),
                     icon: "play.rectangle.fill", tint: Theme.jellyfin)
            StatTile(title: "Albums", value: (jellyfin.counts?.AlbumCount ?? 0).formatted(),
                     subtitle: "\((jellyfin.counts?.SongCount ?? 0).formatted()) songs",
                     icon: "opticaldisc.fill", tint: Theme.jellyfin)
            StatTile(title: "Total items", value: (jellyfin.counts?.ItemCount ?? 0).formatted(),
                     icon: "square.stack.3d.up.fill", tint: .accentColor)
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Scheduled tasks", subtitle: "Trigger a Jellyfin maintenance task")
            VStack(spacing: 0) {
                ForEach(relevantTasks) { task in
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.2")
                            .foregroundStyle(Theme.jellyfin)
                            .font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.Name ?? "Task").font(.system(size: 12))
                            if let state = task.State, state != "Idle" {
                                Text(state).font(.system(size: 9)).foregroundStyle(Theme.warning)
                            }
                        }
                        Spacer()
                        if let progress = task.CurrentProgressPercentage, progress > 0 {
                            Text("\(Int(progress))%")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Button("Run") { Task { await jellyfin.runTask(task) } }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 7)
                    if task.id != relevantTasks.last?.id { Divider() }
                }
            }
            .card()
        }
    }

    private var relevantTasks: [JellyfinScheduledTask] {
        let keys = ["RefreshLibrary", "RefreshPeople", "RefreshChannels", "TmdbRefreshUpcomingEpisodes",
                    "TaskExtractMediaSegments", "TaskCleanCache", "TaskOptimizeDatabase"]
        let filtered = jellyfin.tasks.filter { keys.contains($0.Key ?? "") }
        return filtered.isEmpty ? Array(jellyfin.tasks.prefix(6)) : filtered
    }
}

private struct LibraryCard: View {
    let folder: JellyfinVirtualFolder

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jellyfin: JellyfinStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.jellyfin)
                Text(folder.Name ?? "Library")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Pill(text: (folder.CollectionType ?? "mixed").capitalized, tint: Theme.jellyfin)
            }
            ForEach(folder.Locations ?? [], id: \.self) { path in
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack(spacing: 6) {
                Button {
                    jellyfin.selectedLibraryID = folder.ItemId
                    jellyfin.typeFilter = .auto
                    app.selection = .jellyfinBrowse
                } label: {
                    Label("Browse", systemImage: "square.grid.2x2")
                }
                Button {
                    Task { await jellyfin.scanLibrary(folder) }
                } label: {
                    Label("Scan", systemImage: "arrow.triangle.2.circlepath")
                }
                Menu {
                    Button("Refresh missing metadata") {
                        Task { await refresh(replace: false, images: .standard) }
                    }
                    Button("Replace all metadata") {
                        Task { await refresh(replace: true, images: .standard) }
                    }
                    Button("Replace all metadata and images") {
                        Task { await refresh(replace: true, images: .full) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .controlSize(.small)
        }
        .card()
    }

    private var icon: String {
        switch folder.CollectionType {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note.list"
        case "playlists": return "list.bullet.rectangle"
        default: return "folder"
        }
    }

    private func refresh(replace: Bool, images: JellyfinRefreshMode) async {
        guard let id = folder.ItemId else { return }
        _ = await jellyfin.refreshItem(id: id,
                                       metadata: replace ? .full : .standard,
                                       images: images,
                                       replaceMetadata: replace,
                                       replaceImages: images == .full,
                                       recursive: true)
    }
}
