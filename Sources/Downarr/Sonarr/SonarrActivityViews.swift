import SwiftUI

struct SonarrWantedView: View {
    @EnvironmentObject private var sonarr: SonarrStore
    @State private var searchTarget: SonarrEpisode?

    var body: some View {
        PageScaffold(title: "Wanted episodes",
                     subtitle: "\(sonarr.missing.count) monitored episodes without a file") {
            HStack {
                Button {
                    let ids = sonarr.missing.prefix(30).map(\.id)
                    Task { await sonarr.searchEpisodes(Array(ids)) }
                } label: {
                    Label("Search first 30", systemImage: "magnifyingglass")
                }
                .disabled(sonarr.missing.isEmpty)
                Button {
                    Task { await sonarr.loadMissing() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            if sonarr.missing.isEmpty {
                EmptyStateView(icon: "checkmark.seal",
                               title: "Nothing wanted",
                               message: "Every monitored episode that has aired is on disk.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sonarr.missing) { episode in
                            HStack(spacing: 10) {
                                RemoteImage(url: episode.series.flatMap { sonarr.posterURL($0) },
                                            systemPlaceholder: "tv")
                                    .frame(width: 30, height: 45)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(episode.series?.title ?? "Unknown series")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(episode.code) · \(episode.title ?? "TBA")")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(Fmt.date(episode.airDateUtc))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Button {
                                    Task { await sonarr.searchEpisodes([episode.id]) }
                                } label: {
                                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("Automatic search")
                                Button {
                                    searchTarget = episode
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
        .task { await sonarr.loadMissing() }
        .sheet(item: $searchTarget) { episode in
            InteractiveSearchSheet(
                title: "\(episode.series?.title ?? "") \(episode.code)",
                tint: Theme.sonarr,
                load: { await sonarr.releases(episodeID: episode.id) },
                grab: { await sonarr.grab($0) })
        }
    }
}

struct SonarrHistoryView: View {
    @EnvironmentObject private var sonarr: SonarrStore

    var body: some View {
        PageScaffold(title: "Sonarr history",
                     subtitle: "Most recent \(sonarr.history.count) events") {
            Button {
                Task { await sonarr.loadHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        } content: {
            if sonarr.history.isEmpty {
                LoadingOverlay(text: "Loading history…")
            } else {
                Table(sonarr.history) {
                    TableColumn("When") { Text(Fmt.ago($0.date)).foregroundStyle(.secondary) }
                        .width(80)
                    TableColumn("Event") { record in
                        Pill(text: eventLabel(record.eventType), tint: eventTint(record.eventType))
                    }
                    .width(110)
                    TableColumn("Series") { Text($0.series?.title ?? "—").lineLimit(1) }
                        .width(180)
                    TableColumn("Episode") { record in
                        Text(record.episode.map { "\($0.code) \($0.title ?? "")" } ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn("Quality") { Text($0.quality?.name ?? "—").foregroundStyle(.secondary) }
                        .width(110)
                    TableColumn("Source") { Text($0.sourceTitle ?? "—").foregroundStyle(.tertiary).lineLimit(1) }
                }
                .tableStyle(.inset)
            }
        }
        .task { await sonarr.loadHistory() }
    }
}

func eventLabel(_ raw: String?) -> String {
    switch (raw ?? "").lowercased() {
    case "grabbed": return "Grabbed"
    case "downloadfolderimported", "moviefileimported": return "Imported"
    case "downloadfailed": return "Failed"
    case "episodefiledeleted", "moviefiledeleted": return "Deleted"
    case "downloadignored": return "Ignored"
    case "episodefilerenamed", "moviefilerenamed": return "Renamed"
    default: return (raw ?? "—").capitalized
    }
}

func eventTint(_ raw: String?) -> Color {
    switch (raw ?? "").lowercased() {
    case "grabbed": return Theme.sonarr
    case "downloadfolderimported", "moviefileimported": return Theme.positive
    case "downloadfailed": return Theme.danger
    case "episodefiledeleted", "moviefiledeleted": return Theme.warning
    default: return .secondary
    }
}
