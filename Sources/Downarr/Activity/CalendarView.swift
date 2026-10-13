import SwiftUI

/// Combined Sonarr + Radarr schedule, grouped by day.
struct CalendarView: View {
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var radarr: RadarrStore

    @State private var episodes: [SonarrEpisode] = []
    @State private var movies: [RadarrMovie] = []
    @State private var range: Range = .twoWeeks
    @State private var loading = false

    private enum Range: String, CaseIterable, Identifiable {
        case week, twoWeeks, month, past
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week: return "7 days"
            case .twoWeeks: return "14 days"
            case .month: return "30 days"
            case .past: return "Last 7 days"
            }
        }
        var offsets: (Int, Int) {
            switch self {
            case .week: return (0, 7)
            case .twoWeeks: return (0, 14)
            case .month: return (0, 30)
            case .past: return (-7, 0)
            }
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let date: Date
        let title: String
        let subtitle: String
        let imageURL: URL?
        let tint: Color
        let hasFile: Bool
        let isMonitored: Bool
        let badge: String?
    }

    var body: some View {
        PageScaffold(title: "Calendar", subtitle: "\(entries.count) scheduled items") {
            HStack(spacing: 8) {
                Picker("", selection: $range) {
                    ForEach(Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if loading && entries.isEmpty {
                    LoadingOverlay(text: "Loading calendar…")
                } else if entries.isEmpty {
                    EmptyStateView(icon: "calendar",
                                   title: "Nothing scheduled",
                                   message: "No monitored episodes or movies land in this window.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(groupedDays, id: \.0) { day, items in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text(dayTitle(day))
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(Fmt.shortDate.string(from: day))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(items.count)")
                                            .font(.system(size: 10, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .hairline()
                                    ForEach(items) { entry in
                                        HStack(spacing: 10) {
                                            RemoteImage(url: entry.imageURL, systemPlaceholder: "film")
                                                .frame(width: 32, height: 48)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.title)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .lineLimit(1)
                                                Text(entry.subtitle)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            if let badge = entry.badge {
                                                Pill(text: badge, tint: entry.tint)
                                            }
                                            if entry.hasFile {
                                                Pill(text: "On disk", tint: Theme.positive, icon: "checkmark")
                                            } else if !entry.isMonitored {
                                                Pill(text: "Unmonitored", tint: .secondary)
                                            }
                                            Text(Fmt.timeOnly.string(from: entry.date))
                                                .font(.system(size: 10, design: .rounded))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 54, alignment: .trailing)
                                        }
                                        .padding(8)
                                        .card(padding: 8, radius: 8)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    private var entries: [Entry] {
        var result: [Entry] = episodes.compactMap { episode in
            guard let date = episode.airDateUtc else { return nil }
            return Entry(id: "ep-\(episode.id)",
                         date: date,
                         title: episode.series?.title ?? "Unknown series",
                         subtitle: "\(episode.code) · \(episode.title ?? "TBA")",
                         imageURL: episode.series.flatMap { sonarr.posterURL($0) },
                         tint: Theme.sonarr,
                         hasFile: episode.hasFile ?? false,
                         isMonitored: episode.monitored ?? false,
                         badge: episode.finaleType.map { $0.capitalized + " finale" })
        }
        result += movies.compactMap { movie in
            guard let date = movie.availabilityDate else { return nil }
            return Entry(id: "mv-\(movie.id ?? 0)",
                         date: date,
                         title: movie.title,
                         subtitle: movie.studio ?? "Movie",
                         imageURL: radarr.posterURL(movie),
                         tint: Theme.radarr,
                         hasFile: movie.hasFile ?? false,
                         isMonitored: movie.monitored,
                         badge: movie.inCinemas.map { _ in "Cinema" })
        }
        return result.sorted { $0.date < $1.date }
    }

    private var groupedDays: [(Date, [Entry])] {
        let calendar = Foundation.Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Foundation.Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day)
    }

    private func load() async {
        loading = true
        let calendar = Foundation.Calendar.current
        let (from, to) = range.offsets
        let start = calendar.date(byAdding: .day, value: from, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .day, value: to, to: Date()) ?? Date()
        async let eps = sonarr.calendar(start: start, end: end)
        async let mvs = radarr.calendar(start: start, end: end)
        episodes = await eps
        movies = await mvs
        loading = false
    }
}
