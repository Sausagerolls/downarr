import SwiftUI

struct RadarrLibraryView: View {
    @EnvironmentObject private var radarr: RadarrStore

    @State private var showList = false
    @State private var showAdd = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        PageScaffold(title: "Movies",
                     subtitle: subtitle,
                     error: radarr.libraryState.errorMessage,
                     onRetry: { Task { await radarr.loadAll(force: true) } }) {
            HStack(spacing: 8) {
                LibraryToolbar(filter: $radarr.filter,
                               sortKey: $radarr.sortKey,
                               ascending: $radarr.sortAscending,
                               showList: $showList)
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    Task { await radarr.loadAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload library")
            }
        } content: {
            Group {
                if radarr.libraryState.isLoading && radarr.movies.isEmpty {
                    LoadingOverlay(text: "Loading movies…")
                } else if radarr.movies.isEmpty {
                    EmptyStateView(icon: "film",
                                   title: "No movies",
                                   message: "Radarr returned an empty library.",
                                   actionLabel: "Add a movie") { showAdd = true }
                } else if showList {
                    listBody
                } else {
                    gridBody
                }
            }
        }
        .searchable(text: $radarr.searchText, placement: .toolbar, prompt: "Search movies")
        .navigationDestination(for: RadarrMovie.self) { movie in
            RadarrMovieDetailView(movieID: movie.id ?? 0)
        }
        .sheet(isPresented: $showAdd) {
            RadarrAddMovieView()
        }
        .task { await radarr.loadAll() }
    }

    private var subtitle: String {
        "\(radarr.filteredMovies.count) of \(radarr.movies.count) · \(Fmt.bytes(radarr.totalSize)) · \(radarr.missingCount) missing"
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(radarr.filteredMovies) { movie in
                    NavigationLink(value: movie) {
                        PosterCard(title: movie.title,
                                   subtitle: "\(movie.displayYear)\(movie.qualityName.map { " · \($0)" } ?? "")",
                                   imageURL: radarr.posterURL(movie),
                                   badge: (movie.hasFile ?? false) ? nil : "Missing",
                                   badgeTint: Theme.warning,
                                   progress: nil,
                                   dimmed: !movie.monitored,
                                   placeholderIcon: "film")
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(movie) }
                }
            }
            .padding(18)
        }
    }

    private var listBody: some View {
        Table(radarr.filteredMovies) {
            TableColumn("Title") { movie in
                HStack(spacing: 8) {
                    RemoteImage(url: radarr.posterURL(movie), systemPlaceholder: "film")
                        .frame(width: 22, height: 33)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    NavigationLink(value: movie) {
                        Text(movie.title).lineLimit(1)
                    }
                    .buttonStyle(.link)
                    if !movie.monitored {
                        Image(systemName: "bell.slash").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
            TableColumn("Year") { Text($0.displayYear).foregroundStyle(.secondary) }
                .width(50)
            TableColumn("Studio") { Text($0.studio ?? "—").foregroundStyle(.secondary).lineLimit(1) }
                .width(140)
            TableColumn("Quality") { movie in
                if let quality = movie.qualityName {
                    Pill(text: quality, tint: Theme.positive)
                } else {
                    Pill(text: "Missing", tint: Theme.warning)
                }
            }
            .width(110)
            TableColumn("Size") { Text(Fmt.bytes($0.sizeOnDisk)).foregroundStyle(.secondary) }
                .width(80)
            TableColumn("Rating") { movie in
                Text(movie.ratings?.best.map { String(format: "%.1f", $0) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(60)
            TableColumn("Added") { Text(Fmt.date($0.added)).foregroundStyle(.secondary) }
                .width(100)
        }
        .tableStyle(.inset)
    }

    @ViewBuilder
    private func contextMenu(_ movie: RadarrMovie) -> some View {
        if let id = movie.id {
            Button(movie.monitored ? "Stop monitoring" : "Start monitoring") {
                Task { await radarr.setMonitored(movieID: id, monitored: !movie.monitored) }
            }
            Button("Search") { Task { await radarr.search(movieIDs: [id]) } }
            Button("Refresh metadata") { Task { await radarr.refresh(movieID: id) } }
            Button("Rescan files") { Task { await radarr.rescan(movieID: id) } }
            if let path = movie.path {
                Divider()
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        }
    }
}
