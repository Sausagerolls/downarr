import SwiftUI

struct SonarrAddSeriesView: View {
    @EnvironmentObject private var sonarr: SonarrStore
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var results: [SonarrSeries] = []
    @State private var searching = false
    @State private var selected: SonarrSeries?

    // Add options
    @State private var rootFolder = ""
    @State private var profileID = 1
    @State private var monitorStrategy: SonarrMonitorStrategy = .all
    @State private var seasonFolder = true
    @State private var searchOnAdd = true
    @State private var seriesType = "standard"
    @State private var adding = false

    var body: some View {
        HSplitView {
            searchPane
                .frame(minWidth: 380, idealWidth: 420)
            detailPane
                .frame(minWidth: 380)
        }
        .frame(width: 900, height: 620)
        .task {
            await sonarr.loadAll()
            rootFolder = sonarr.rootFolders.first?.path ?? ""
            profileID = sonarr.profiles.first(where: { $0.name.contains("1080") })?.id
                ?? sonarr.profiles.first?.id ?? 1
        }
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add series").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search TheTVDB", text: $term)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            if results.isEmpty {
                EmptyStateView(icon: "tv.badge.wifi",
                               title: "Find a series",
                               message: "Type a title and press return.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(results, id: \.tvdbId) { series in
                            Button {
                                selected = series
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: sonarr.lookupPosterURL(series), systemPlaceholder: "tv")
                                        .frame(width: 40, height: 60)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(series.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text([series.displayYear, series.network ?? "", series.status?.capitalized ?? ""]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        if series.id != nil {
                                            Pill(text: "Already in Sonarr", tint: Theme.positive)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected?.tvdbId == series.tvdbId
                                              ? Theme.sonarr.opacity(0.14) : Color.clear)
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
            if let series = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage(url: sonarr.lookupPosterURL(series), systemPlaceholder: "tv")
                                .frame(width: 90, height: 135)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(series.title).font(.system(size: 17, weight: .semibold))
                                HStack(spacing: 5) {
                                    Pill(text: series.displayYear, tint: Theme.sonarr)
                                    if let network = series.network { Pill(text: network, tint: .secondary) }
                                    if let rating = series.ratings?.value, rating > 0 {
                                        Pill(text: String(format: "★ %.1f", rating), tint: Theme.radarr)
                                    }
                                }
                                if let genres = series.genres, !genres.isEmpty {
                                    Text(genres.prefix(4).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let overview = series.overview {
                            Text(overview).font(.caption).foregroundStyle(.secondary)
                        }

                        Form {
                            Picker("Root folder", selection: $rootFolder) {
                                ForEach(sonarr.rootFolders) { folder in
                                    Text("\(folder.path)  (\(Fmt.bytes(folder.freeSpace)) free)").tag(folder.path)
                                }
                            }
                            Picker("Quality profile", selection: $profileID) {
                                ForEach(sonarr.profiles) { Text($0.name).tag($0.id) }
                            }
                            Picker("Monitor", selection: $monitorStrategy) {
                                ForEach(SonarrMonitorStrategy.allCases) { Text($0.label).tag($0) }
                            }
                            Picker("Series type", selection: $seriesType) {
                                Text("Standard").tag("standard")
                                Text("Daily").tag("daily")
                                Text("Anime").tag("anime")
                            }
                            Toggle("Season folders", isOn: $seasonFolder)
                            Toggle("Search for missing episodes after adding", isOn: $searchOnAdd)
                        }
                        .formStyle(.grouped)
                        .frame(height: 300)

                        HStack {
                            Spacer()
                            Button {
                                Task { await add(series) }
                            } label: {
                                if adding {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(series.id == nil ? "Add series" : "Already added",
                                          systemImage: "plus.circle.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.sonarr)
                            .disabled(adding || series.id != nil || rootFolder.isEmpty)
                        }
                    }
                    .padding(16)
                }
            } else {
                EmptyStateView(icon: "hand.point.left",
                               title: "Pick a result",
                               message: "Choose a series on the left to set its options.")
            }
        }
    }

    private func runSearch() async {
        searching = true
        results = await sonarr.lookup(term)
        searching = false
    }

    private func add(_ series: SonarrSeries) async {
        guard let tvdbID = series.tvdbId else { return }
        adding = true
        let request = SonarrAddSeriesRequest(
            title: series.title,
            tvdbId: tvdbID,
            titleSlug: series.titleSlug,
            year: series.year,
            qualityProfileId: profileID,
            rootFolderPath: rootFolder,
            monitored: monitorStrategy != .none,
            seasonFolder: seasonFolder,
            seriesType: seriesType,
            images: series.images ?? [],
            seasons: series.seasons ?? [],
            addOptions: SonarrAddOptions(monitor: monitorStrategy.rawValue,
                                         searchForMissingEpisodes: searchOnAdd))
        let ok = await sonarr.addSeries(request)
        adding = false
        if ok { dismiss() }
    }
}
