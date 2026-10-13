import SwiftUI

struct JellyfinItemDetailView: View {
    let itemID: String

    @EnvironmentObject private var jellyfin: JellyfinStore

    @State private var item: JellyfinItem?
    @State private var children: [JellyfinItem] = []
    @State private var childLabel = ""
    @State private var showEditor = false
    @State private var showIdentify = false
    @State private var showImages = false
    @State private var showDelete = false
    @State private var loading = true

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(item)
                        VStack(alignment: .leading, spacing: 18) {
                            if let overview = item.Overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            metadataSection(item)
                            if let stream = item.videoStream { mediaSection(item, stream: stream) }
                            if !children.isEmpty { childrenSection(item) }
                            if let people = item.People, !people.isEmpty { peopleSection(people) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else if loading {
                LoadingOverlay(text: "Loading item…")
            } else {
                EmptyStateView(icon: "questionmark.folder",
                               title: "Item unavailable",
                               message: "Jellyfin did not return this item.")
            }
        }
        .navigationTitle(item?.Name ?? "Item")
        .task { await reload() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await reload() } }) {
            if let item { JellyfinMetadataEditor(item: item) }
        }
        .sheet(isPresented: $showIdentify, onDismiss: { Task { await reload() } }) {
            if let item { JellyfinIdentifySheet(item: item) }
        }
        .sheet(isPresented: $showImages, onDismiss: { Task { await reload() } }) {
            if let item { JellyfinImagesSheet(item: item) }
        }
        .alert("Delete \(item?.Name ?? "item") from Jellyfin?", isPresented: $showDelete) {
            Button("Delete media", role: .destructive) {
                Task { _ = await jellyfin.deleteItem(id: itemID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the underlying file from disk. It cannot be undone.")
        }
    }

    // MARK: Sections

    private func header(_ item: JellyfinItem) -> some View {
        DetailHeader(backdropURL: jellyfin.backdropURL(item),
                     posterURL: jellyfin.posterURL(item),
                     tint: Theme.jellyfin) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.Name ?? "Untitled")
                    .font(.system(size: 25, weight: .bold))
                    .lineLimit(2)
                if let series = item.SeriesName, item.kind == .episode || item.kind == .season {
                    Text(series).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Pill(text: item.kind.rawValue.isEmpty ? "Item" : item.kind.rawValue,
                         tint: Theme.jellyfin, filled: true)
                    if let year = item.ProductionYear { Pill(text: String(year), tint: .white) }
                    if let rating = item.OfficialRating { Pill(text: rating, tint: .white) }
                    if let community = item.CommunityRating {
                        Pill(text: String(format: "★ %.1f", community), tint: Theme.radarr, filled: true)
                    }
                    if item.RunTimeTicks != nil { Pill(text: item.runtimeText, tint: .white, icon: "clock") }
                    if item.isLocked { Pill(text: "Locked", tint: Theme.warning, filled: true) }
                }
                HStack(spacing: 8) {
                    Button {
                        showEditor = true
                    } label: {
                        Label("Edit metadata", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.jellyfin)

                    Button {
                        showIdentify = true
                    } label: {
                        Label("Fix match", systemImage: "person.fill.viewfinder")
                    }
                    .disabled(item.kind.remoteSearchPath == nil)

                    Button {
                        showImages = true
                    } label: {
                        Label("Images", systemImage: "photo.on.rectangle.angled")
                    }

                    Menu {
                        Button("Refresh missing metadata") {
                            Task { await refresh(metadata: .standard, images: .standard, replace: false) }
                        }
                        Button("Replace all metadata") {
                            Task { await refresh(metadata: .full, images: .standard, replace: true) }
                        }
                        Button("Replace metadata and images") {
                            Task { await refresh(metadata: .full, images: .full, replace: true) }
                        }
                        Divider()
                        if let path = item.Path {
                            Button("Copy file path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }
                        }
                        ForEach(providerLinks(item), id: \.0) { link in
                            Link(link.0, destination: link.1)
                        }
                        Divider()
                        Button("Delete from Jellyfin…", role: .destructive) { showDelete = true }
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

    private func metadataSection(_ item: JellyfinItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Metadata",
                          subtitle: item.isLocked ? "Locked — scheduled refreshes will not overwrite it" : nil,
                          action: { showEditor = true }, actionLabel: "Edit")
            VStack(alignment: .leading, spacing: 6) {
                KeyValueRow(key: "Sort title", value: item.SortName ?? "—")
                KeyValueRow(key: "Original title", value: item.OriginalTitle ?? "—")
                KeyValueRow(key: "Premiere", value: Fmt.date(item.PremiereDate))
                KeyValueRow(key: "Added", value: Fmt.dateTime(item.DateCreated))
                if let tagline = item.Taglines?.first, !tagline.isEmpty {
                    KeyValueRow(key: "Tagline", value: tagline)
                }
                if let genres = item.Genres, !genres.isEmpty {
                    KeyValueRow(key: "Genres", value: genres.joined(separator: ", "))
                }
                if let studios = item.Studios?.compactMap(\.Name), !studios.isEmpty {
                    KeyValueRow(key: "Studios", value: studios.joined(separator: ", "))
                }
                if let tags = item.Tags, !tags.isEmpty {
                    KeyValueRow(key: "Tags", value: tags.joined(separator: ", "))
                }
                if let ids = item.ProviderIds, !ids.isEmpty {
                    KeyValueRow(key: "Provider IDs",
                                value: ids.sorted(by: { $0.key < $1.key })
                                    .map { "\($0.key): \($0.value)" }
                                    .joined(separator: "   "))
                }
                if let locked = item.LockedFields, !locked.isEmpty {
                    KeyValueRow(key: "Locked fields", value: locked.joined(separator: ", "),
                                valueColor: Theme.warning)
                }
                KeyValueRow(key: "Path", value: item.Path ?? "—")
            }
            .card()
        }
    }

    private func mediaSection(_ item: JellyfinItem, stream: JellyfinMediaStream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Media")
            VStack(alignment: .leading, spacing: 6) {
                KeyValueRow(key: "Container", value: (item.Container ?? "—").uppercased())
                KeyValueRow(key: "Video", value: [stream.DisplayTitle, stream.Codec?.uppercased()]
                    .compactMap { $0 }.joined(separator: " · "))
                KeyValueRow(key: "Resolution",
                            value: [stream.Width, stream.Height].compactMap { $0 }.count == 2
                                ? "\(stream.Width ?? 0)×\(stream.Height ?? 0)" : "—")
                if !item.audioStreams.isEmpty {
                    KeyValueRow(key: "Audio",
                                value: item.audioStreams.compactMap(\.DisplayTitle).joined(separator: "\n"))
                }
                if !item.subtitleStreams.isEmpty {
                    KeyValueRow(key: "Subtitles",
                                value: item.subtitleStreams.compactMap { $0.DisplayTitle ?? $0.Language }
                                    .joined(separator: ", "))
                }
                KeyValueRow(key: "File size", value: Fmt.bytes(item.fileSize))
            }
            .card()
        }
    }

    private func childrenSection(_ item: JellyfinItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: childLabel, subtitle: "\(children.count) items")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)],
                      alignment: .leading, spacing: 14) {
                ForEach(children) { child in
                    NavigationLink(value: child) {
                        PosterCard(title: child.displayName,
                                   subtitle: child.kind == .season
                                       ? "\(child.ChildCount ?? 0) episodes"
                                       : Fmt.ticks(child.RunTimeTicks),
                                   imageURL: jellyfin.posterURL(child, maxHeight: 300),
                                   width: 120,
                                   badge: child.isLocked ? "Locked" : nil,
                                   badgeTint: Theme.warning,
                                   placeholderIcon: child.kind.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func peopleSection(_ people: [JellyfinPerson]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cast & crew", subtitle: "\(people.count) credited")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(people.prefix(24)) { person in
                        VStack(spacing: 4) {
                            RemoteImage(url: person.Id.flatMap {
                                jellyfin.imageURL(itemID: $0, type: "Primary", maxHeight: 180)
                            }, systemPlaceholder: "person.fill")
                                .frame(width: 58, height: 58)
                                .clipShape(Circle())
                            Text(person.Name ?? "—")
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                            Text(person.Role ?? person.PersonType ?? "")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 66)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Data

    private func reload() async {
        loading = true
        item = await jellyfin.item(id: itemID)
        if let item {
            switch item.kind {
            case .series:
                children = await jellyfin.seasons(seriesID: item.Id)
                childLabel = "Seasons"
            case .season:
                children = await jellyfin.episodes(seriesID: item.SeriesId ?? "", seasonID: item.Id)
                childLabel = "Episodes"
            case .boxSet, .musicArtist, .musicAlbum:
                children = await jellyfin.children(parentID: item.Id)
                childLabel = "Contents"
            default:
                children = []
                childLabel = ""
            }
        }
        loading = false
    }

    private func refresh(metadata: JellyfinRefreshMode, images: JellyfinRefreshMode, replace: Bool) async {
        _ = await jellyfin.refreshItem(id: itemID, metadata: metadata, images: images,
                                       replaceMetadata: replace,
                                       replaceImages: images == .full,
                                       recursive: item?.IsFolder ?? false)
    }

    private func providerLinks(_ item: JellyfinItem) -> [(String, URL)] {
        var links: [(String, URL)] = []
        if let imdb = item.ProviderIds?["Imdb"], let url = URL(string: "https://www.imdb.com/title/\(imdb)") {
            links.append(("Open on IMDb", url))
        }
        if let tmdb = item.ProviderIds?["Tmdb"] {
            let path = item.kind == .movie ? "movie" : "tv"
            if let url = URL(string: "https://www.themoviedb.org/\(path)/\(tmdb)") {
                links.append(("Open on TMDB", url))
            }
        }
        if let tvdb = item.ProviderIds?["Tvdb"],
           let url = URL(string: "https://thetvdb.com/dereferrer/series/\(tvdb)") {
            links.append(("Open on TheTVDB", url))
        }
        return links
    }
}
