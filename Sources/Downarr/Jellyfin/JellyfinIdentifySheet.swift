import SwiftUI

/// "Fix match" — search the metadata providers and apply a different identity to the item.
struct JellyfinIdentifySheet: View {
    let item: JellyfinItem

    @EnvironmentObject private var jellyfin: JellyfinStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var year: String
    @State private var imdb: String
    @State private var tmdb: String
    @State private var tvdb: String
    @State private var indexNumber: String
    @State private var parentIndexNumber: String
    @State private var replaceImages = true

    @State private var results: [JellyfinRemoteSearchResult] = []
    @State private var searching = false
    @State private var applying: String?
    @State private var hasSearched = false

    init(item: JellyfinItem) {
        self.item = item
        _name = State(initialValue: item.Name ?? "")
        _year = State(initialValue: item.ProductionYear.map(String.init) ?? "")
        _imdb = State(initialValue: item.ProviderIds?["Imdb"] ?? "")
        _tmdb = State(initialValue: item.ProviderIds?["Tmdb"] ?? "")
        _tvdb = State(initialValue: item.ProviderIds?["Tvdb"] ?? "")
        _indexNumber = State(initialValue: item.IndexNumber.map(String.init) ?? "")
        _parentIndexNumber = State(initialValue: item.ParentIndexNumber.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Identify").font(.headline)
                    Text("\(item.displayName) · \(item.kind.rawValue)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            .hairline()

            searchForm

            Divider()

            if searching {
                LoadingOverlay(text: "Asking metadata providers…")
            } else if results.isEmpty {
                EmptyStateView(icon: hasSearched ? "questionmark.circle" : "person.fill.viewfinder",
                               title: hasSearched ? "No matches" : "Search for the correct match",
                               message: hasSearched
                                   ? "Try a different spelling, drop the year, or paste a provider ID above."
                                   : "Adjust the details above and hit Search. Applying a match replaces the item's identity and re-downloads its metadata.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { result in
                            ResultRow(result: result,
                                      isApplying: applying == result.id,
                                      apply: { apply(result) })
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 880, height: 680)
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                field("Name", text: $name, width: 260)
                field("Year", text: $year, width: 70)
                if item.kind == .episode {
                    field("Season", text: $parentIndexNumber, width: 60)
                    field("Episode", text: $indexNumber, width: 60)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                field("IMDb ID", text: $imdb, width: 130)
                field("TMDB ID", text: $tmdb, width: 110)
                field("TVDB ID", text: $tvdb, width: 110)
                Spacer()
                Toggle("Replace images", isOn: $replaceImages)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button {
                    Task { await search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.jellyfin)
                .keyboardShortcut(.defaultAction)
                .disabled(searching)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(14)
    }

    private func field(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
            TextField("", text: text).frame(width: width)
        }
    }

    private func search() async {
        searching = true
        hasSearched = true
        var ids: [String: String] = [:]
        if !imdb.isEmpty { ids["Imdb"] = imdb }
        if !tmdb.isEmpty { ids["Tmdb"] = tmdb }
        if !tvdb.isEmpty { ids["Tvdb"] = tvdb }
        results = await jellyfin.identify(item: item,
                                          name: name,
                                          year: Int(year),
                                          providerIDs: ids,
                                          indexNumber: Int(indexNumber),
                                          parentIndexNumber: Int(parentIndexNumber))
        searching = false
    }

    private func apply(_ result: JellyfinRemoteSearchResult) {
        applying = result.id
        Task {
            let ok = await jellyfin.applyIdentification(itemID: item.Id,
                                                        result: result,
                                                        replaceImages: replaceImages)
            applying = nil
            if ok { dismiss() }
        }
    }
}

private struct ResultRow: View {
    let result: JellyfinRemoteSearchResult
    let isApplying: Bool
    let apply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: result.ImageUrl.flatMap(URL.init(string:)), systemPlaceholder: "film")
                .frame(width: 60, height: 90)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(result.Name ?? "Untitled")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let year = result.ProductionYear {
                        Text(String(year)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    if let provider = result.SearchProviderName {
                        Pill(text: provider, tint: Theme.jellyfin)
                    }
                    ForEach((result.ProviderIds ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        Pill(text: "\(pair.key) \(pair.value)", tint: .secondary)
                    }
                    if let index = result.IndexNumber {
                        Pill(text: "Episode \(index)", tint: .secondary)
                    }
                }
                if let overview = result.Overview, !overview.isEmpty {
                    Text(overview.replacingOccurrences(of: "<br>", with: " "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Button {
                apply()
            } label: {
                if isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Apply")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isApplying)
        }
        .padding(11)
        .card(padding: 11, radius: 10)
    }
}
