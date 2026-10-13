import SwiftUI

struct RadarrWantedView: View {
    @EnvironmentObject private var radarr: RadarrStore
    @State private var searchTarget: RadarrMovie?

    var body: some View {
        PageScaffold(title: "Wanted movies",
                     subtitle: "\(radarr.missing.count) monitored movies without a file") {
            HStack {
                Button {
                    let ids = radarr.missing.prefix(30).compactMap(\.id)
                    Task { await radarr.search(movieIDs: Array(ids)) }
                } label: {
                    Label("Search first 30", systemImage: "magnifyingglass")
                }
                .disabled(radarr.missing.isEmpty)
                Button {
                    Task { await radarr.loadMissing() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            if radarr.missing.isEmpty {
                EmptyStateView(icon: "checkmark.seal",
                               title: "Nothing wanted",
                               message: "Every monitored, available movie is on disk.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(radarr.missing) { movie in
                            HStack(spacing: 10) {
                                RemoteImage(url: radarr.posterURL(movie), systemPlaceholder: "film")
                                    .frame(width: 30, height: 45)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(movie.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text([movie.displayYear, movie.studio ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if movie.isAvailable ?? false {
                                    Pill(text: "Available", tint: Theme.positive)
                                } else {
                                    Pill(text: Fmt.date(movie.availabilityDate), tint: .secondary, icon: "calendar")
                                }
                                Button {
                                    if let id = movie.id { Task { await radarr.search(movieIDs: [id]) } }
                                } label: {
                                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("Automatic search")
                                Button {
                                    searchTarget = movie
                                } label: {
                                    Image(systemName: "person.fill.viewfinder").font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("Manual search")
                            }
                            .padding(8)
                            .card(padding: 8, radius: 8)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .task { await radarr.loadMissing() }
        .sheet(item: $searchTarget) { movie in
            InteractiveSearchSheet(
                title: "\(movie.title) (\(movie.displayYear))",
                tint: Theme.radarr,
                load: { await radarr.releases(movieID: movie.id ?? 0) },
                grab: { await radarr.grab($0) })
        }
    }
}

struct RadarrHistoryView: View {
    @EnvironmentObject private var radarr: RadarrStore

    var body: some View {
        PageScaffold(title: "Radarr history",
                     subtitle: "Most recent \(radarr.history.count) events") {
            Button {
                Task { await radarr.loadHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        } content: {
            if radarr.history.isEmpty {
                LoadingOverlay(text: "Loading history…")
            } else {
                Table(radarr.history) {
                    TableColumn("When") { Text(Fmt.ago($0.date)).foregroundStyle(.secondary) }
                        .width(80)
                    TableColumn("Event") { record in
                        Pill(text: eventLabel(record.eventType), tint: eventTint(record.eventType))
                    }
                    .width(110)
                    TableColumn("Movie") { Text($0.movie?.title ?? "—").lineLimit(1) }
                        .width(220)
                    TableColumn("Quality") { Text($0.quality?.name ?? "—").foregroundStyle(.secondary) }
                        .width(110)
                    TableColumn("Source") { Text($0.sourceTitle ?? "—").foregroundStyle(.tertiary).lineLimit(1) }
                }
                .tableStyle(.inset)
            }
        }
        .task { await radarr.loadHistory() }
    }
}
