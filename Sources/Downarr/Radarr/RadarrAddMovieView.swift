import SwiftUI

struct RadarrAddMovieView: View {
    @EnvironmentObject private var radarr: RadarrStore
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var results: [RadarrMovie] = []
    @State private var searching = false
    @State private var selected: RadarrMovie?

    @State private var rootFolder = ""
    @State private var profileID = 1
    @State private var availability: String = RadarrAvailability.released.rawValue
    @State private var monitored = true
    @State private var searchOnAdd = true
    @State private var adding = false

    var body: some View {
        HSplitView {
            searchPane.frame(minWidth: 380, idealWidth: 420)
            detailPane.frame(minWidth: 380)
        }
        .frame(width: 900, height: 620)
        .task {
            await radarr.loadAll()
            rootFolder = radarr.rootFolders.first?.path ?? ""
            profileID = radarr.profiles.first(where: { $0.name.contains("1080") })?.id
                ?? radarr.profiles.first?.id ?? 1
        }
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add movie").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search TMDB", text: $term)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            if results.isEmpty {
                EmptyStateView(icon: "film.stack",
                               title: "Find a movie",
                               message: "Type a title and press return.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(results, id: \.tmdbId) { movie in
                            Button {
                                selected = movie
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: radarr.lookupPosterURL(movie), systemPlaceholder: "film")
                                        .frame(width: 40, height: 60)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(movie.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text([movie.displayYear, movie.studio ?? ""]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        if movie.id != nil {
                                            Pill(text: "Already in Radarr", tint: Theme.positive)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected?.tmdbId == movie.tmdbId
                                              ? Theme.radarr.opacity(0.16) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let movie = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage(url: radarr.lookupPosterURL(movie), systemPlaceholder: "film")
                                .frame(width: 90, height: 135)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(movie.title).font(.system(size: 17, weight: .semibold))
                                HStack(spacing: 5) {
                                    Pill(text: movie.displayYear, tint: Theme.radarr)
                                    if let rating = movie.ratings?.best {
                                        Pill(text: String(format: "★ %.1f", rating), tint: Theme.warning)
                                    }
                                    Pill(text: Fmt.minutes(movie.runtime), tint: .secondary, icon: "clock")
                                }
                                if let genres = movie.genres, !genres.isEmpty {
                                    Text(genres.prefix(4).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let overview = movie.overview {
                            Text(overview).font(.caption).foregroundStyle(.secondary)
                        }

                        Form {
                            Picker("Root folder", selection: $rootFolder) {
                                ForEach(radarr.rootFolders) { folder in
                                    Text("\(folder.path)  (\(Fmt.bytes(folder.freeSpace)) free)").tag(folder.path)
                                }
                            }
                            Picker("Quality profile", selection: $profileID) {
                                ForEach(radarr.profiles) { Text($0.name).tag($0.id) }
                            }
                            Picker("Minimum availability", selection: $availability) {
                                ForEach(RadarrAvailability.allCases) { Text($0.label).tag($0.rawValue) }
                            }
                            Toggle("Monitored", isOn: $monitored)
                            Toggle("Search for the movie after adding", isOn: $searchOnAdd)
                        }
                        .formStyle(.grouped)
                        .frame(height: 260)

                        HStack {
                            Spacer()
                            Button {
                                Task { await add(movie) }
                            } label: {
                                if adding {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(movie.id == nil ? "Add movie" : "Already added",
                                          systemImage: "plus.circle.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.radarr)
                            .disabled(adding || movie.id != nil || rootFolder.isEmpty)
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptyStateView(icon: "hand.point.left",
                               title: "Pick a result",
                               message: "Choose a movie on the left to set its options.")
            }
        }
    }

    private func runSearch() async {
        searching = true
        results = await radarr.lookup(term)
        searching = false
    }

    private func add(_ movie: RadarrMovie) async {
        guard let tmdbID = movie.tmdbId else { return }
        adding = true
        let request = RadarrAddMovieRequest(
            title: movie.title,
            tmdbId: tmdbID,
            year: movie.year,
            titleSlug: movie.titleSlug,
            qualityProfileId: profileID,
            rootFolderPath: rootFolder,
            monitored: monitored,
            minimumAvailability: availability,
            images: movie.images ?? [],
            addOptions: RadarrAddOptions(searchForMovie: searchOnAdd))
        let ok = await radarr.addMovie(request)
        adding = false
        if ok { dismiss() }
    }
}
