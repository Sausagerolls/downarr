import SwiftUI

struct RadarrMovieDetailView: View {
    let movieID: Int

    @EnvironmentObject private var radarr: RadarrStore
    @State private var showManualSearch = false
    @State private var showEdit = false
    @State private var showDelete = false

    private var movie: RadarrMovie? { radarr.movie(id: movieID) }

    var body: some View {
        Group {
            if let movie {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(movie)
                        VStack(alignment: .leading, spacing: 18) {
                            if let overview = movie.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            factsGrid(movie)
                            if let file = movie.movieFile {
                                fileSection(file, movie: movie)
                            } else {
                                missingSection(movie)
                            }
                            detailsSection(movie)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else {
                LoadingOverlay(text: "Loading movie…")
            }
        }
        .navigationTitle(movie?.title ?? "Movie")
        .task { await radarr.loadAll() }
        .sheet(isPresented: $showManualSearch) {
            InteractiveSearchSheet(
                title: movie.map { "\($0.title) (\($0.displayYear))" } ?? "",
                tint: Theme.radarr,
                load: { await radarr.releases(movieID: movieID) },
                grab: { await radarr.grab($0) })
        }
        .sheet(isPresented: $showEdit) {
            if let movie { RadarrEditMovieSheet(movie: movie) }
        }
        .alert("Remove \(movie?.title ?? "movie")?", isPresented: $showDelete) {
            Button("Remove, keep files") {
                Task { await radarr.deleteMovie(id: movieID, deleteFiles: false, addExclusion: false) }
            }
            Button("Remove and delete files", role: .destructive) {
                Task { await radarr.deleteMovie(id: movieID, deleteFiles: true, addExclusion: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing keeps the file on disk unless you choose to delete it.")
        }
    }

    private func header(_ movie: RadarrMovie) -> some View {
        DetailHeader(backdropURL: radarr.fanartURL(movie),
                     posterURL: radarr.posterURL(movie),
                     tint: Theme.radarr) {
            VStack(alignment: .leading, spacing: 8) {
                Text(movie.title).font(.system(size: 26, weight: .bold)).lineLimit(2)
                if let original = movie.originalTitle, original != movie.title {
                    Text(original).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Pill(text: movie.displayYear, tint: Theme.radarr, filled: true)
                    if let cert = movie.certification { Pill(text: cert, tint: .white) }
                    Pill(text: Fmt.minutes(movie.runtime), tint: .white, icon: "clock")
                    if let rating = movie.ratings?.imdb?.value {
                        Pill(text: String(format: "IMDb %.1f", rating), tint: Theme.radarr, filled: true)
                    }
                    if let tomato = movie.ratings?.rottenTomatoes?.value, tomato > 0 {
                        Pill(text: "RT \(Int(tomato))%", tint: Theme.danger, filled: true)
                    }
                    Pill(text: movie.status?.capitalized ?? "—", tint: .white)
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await radarr.search(movieIDs: [movieID]) }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.radarr)

                    Button {
                        showManualSearch = true
                    } label: {
                        Label("Manual", systemImage: "person.fill.viewfinder")
                    }

                    Button {
                        Task { await radarr.setMonitored(movieID: movieID, monitored: !movie.monitored) }
                    } label: {
                        Label(movie.monitored ? "Monitored" : "Unmonitored",
                              systemImage: movie.monitored ? "bell.fill" : "bell.slash")
                    }

                    Menu {
                        Button("Refresh metadata") { Task { await radarr.refresh(movieID: movieID) } }
                        Button("Rescan files") { Task { await radarr.rescan(movieID: movieID) } }
                        Button("Rename file") { Task { await radarr.rename(movieID: movieID) } }
                        Divider()
                        Button("Edit…") { showEdit = true }
                        Button("Remove from Radarr…", role: .destructive) { showDelete = true }
                        if let imdb = movie.imdbId {
                            Divider()
                            Link("Open on IMDb", destination: URL(string: "https://www.imdb.com/title/\(imdb)")!)
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

    private func factsGrid(_ movie: RadarrMovie) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            StatTile(title: "On disk",
                     value: Fmt.bytes(movie.sizeOnDisk),
                     subtitle: movie.qualityName ?? "no file",
                     icon: "internaldrive",
                     tint: (movie.hasFile ?? false) ? Theme.positive : Theme.warning)
            StatTile(title: "Quality profile",
                     value: radarr.profileName(movie.qualityProfileId),
                     subtitle: "min. \(movie.minimumAvailability ?? "—")",
                     icon: "slider.horizontal.3", tint: .accentColor)
            StatTile(title: "Availability",
                     value: Fmt.date(movie.availabilityDate),
                     subtitle: (movie.isAvailable ?? false) ? "available" : "not yet available",
                     icon: "calendar", tint: Theme.radarr)
            StatTile(title: "Added",
                     value: Fmt.date(movie.added),
                     subtitle: movie.studio,
                     icon: "tray.and.arrow.down", tint: .accentColor)
        }
    }

    private func fileSection(_ file: RadarrMovieFile, movie: RadarrMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "File")
            VStack(alignment: .leading, spacing: 6) {
                KeyValueRow(key: "Path", value: file.relativePath ?? file.path ?? "—")
                KeyValueRow(key: "Quality", value: file.quality?.name ?? "—")
                KeyValueRow(key: "Size", value: Fmt.bytes(file.size))
                if let info = file.mediaInfo {
                    KeyValueRow(key: "Video", value: [info.videoCodec, info.resolution, info.videoDynamicRange]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    KeyValueRow(key: "Audio", value: [info.audioCodec, info.audioChannels.map { "\($0) ch" },
                                                      info.audioLanguages]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    if let subs = info.subtitles, !subs.isEmpty {
                        KeyValueRow(key: "Subtitles", value: subs)
                    }
                }
                if let group = file.releaseGroup { KeyValueRow(key: "Release group", value: group) }
                KeyValueRow(key: "Imported", value: Fmt.dateTime(file.dateAdded))
                HStack {
                    Spacer()
                    Button("Delete file", role: .destructive) {
                        Task { await radarr.deleteMovieFile(id: file.id, movieID: movieID) }
                    }
                    .controlSize(.small)
                }
            }
            .card()
        }
    }

    private func missingSection(_ movie: RadarrMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "No file on disk")
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(movie.monitored
                     ? "Radarr is monitoring this movie and will grab it when a release passes your profile."
                     : "This movie is not monitored, so Radarr will not search for it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manual search") { showManualSearch = true }
                    .controlSize(.small)
            }
            .card()
        }
    }

    private func detailsSection(_ movie: RadarrMovie) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Details")
            VStack(alignment: .leading, spacing: 6) {
                if let genres = movie.genres, !genres.isEmpty {
                    KeyValueRow(key: "Genres", value: genres.joined(separator: ", "))
                }
                KeyValueRow(key: "Path", value: movie.path ?? "—")
                KeyValueRow(key: "In cinemas", value: Fmt.date(movie.inCinemas))
                KeyValueRow(key: "Digital release", value: Fmt.date(movie.digitalRelease))
                KeyValueRow(key: "Physical release", value: Fmt.date(movie.physicalRelease))
                KeyValueRow(key: "TMDB", value: movie.tmdbId.map(String.init) ?? "—")
                KeyValueRow(key: "IMDb", value: movie.imdbId ?? "—")
                if let collection = movie.collection?.title {
                    KeyValueRow(key: "Collection", value: collection)
                }
            }
            .card()
        }
    }
}

struct RadarrEditMovieSheet: View {
    let movie: RadarrMovie

    @EnvironmentObject private var radarr: RadarrStore
    @Environment(\.dismiss) private var dismiss

    @State private var monitored: Bool
    @State private var profileID: Int
    @State private var availability: String
    @State private var path: String

    init(movie: RadarrMovie) {
        self.movie = movie
        _monitored = State(initialValue: movie.monitored)
        _profileID = State(initialValue: movie.qualityProfileId ?? 1)
        _availability = State(initialValue: movie.minimumAvailability ?? "released")
        _path = State(initialValue: movie.path ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit \(movie.title)").font(.headline).padding(16)
            Divider()
            Form {
                Toggle("Monitored", isOn: $monitored)
                Picker("Quality profile", selection: $profileID) {
                    ForEach(radarr.profiles) { Text($0.name).tag($0.id) }
                }
                Picker("Minimum availability", selection: $availability) {
                    ForEach(RadarrAvailability.allCases) { Text($0.label).tag($0.rawValue) }
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
                        await radarr.edit(movieID: movie.id ?? 0, changes: [
                            "monitored": .bool(monitored),
                            "qualityProfileId": .number(Double(profileID)),
                            "minimumAvailability": .string(availability),
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
