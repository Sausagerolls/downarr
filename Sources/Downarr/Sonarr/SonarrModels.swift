import Foundation

struct SonarrRatings: Codable, Hashable {
    var votes: Int?
    var value: Double?
}

struct SonarrSeasonStatistics: Codable, Hashable {
    var episodeFileCount: Int?
    var episodeCount: Int?
    var totalEpisodeCount: Int?
    var sizeOnDisk: Int64?
    var percentOfEpisodes: Double?
    var nextAiring: Date?
    var previousAiring: Date?
}

struct SonarrSeason: Codable, Hashable, Identifiable {
    var seasonNumber: Int
    var monitored: Bool?
    var statistics: SonarrSeasonStatistics?

    var id: Int { seasonNumber }
    var title: String { seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)" }
}

struct SonarrSeriesStatistics: Codable, Hashable {
    var seasonCount: Int?
    var episodeFileCount: Int?
    var episodeCount: Int?
    var totalEpisodeCount: Int?
    var sizeOnDisk: Int64?
    var percentOfEpisodes: Double?
    var releaseGroups: [String]?
}

/// Read model for a series. Writes go through the raw-JSON patch path in `SonarrClient`
/// so unmodelled fields are never clobbered.
struct SonarrSeries: Codable, Identifiable, Hashable {
    var id: Int?
    var title: String = ""
    var sortTitle: String?
    var status: String?
    var ended: Bool?
    var overview: String?
    var network: String?
    var airTime: String?
    var images: [ArrImage]?
    var seasons: [SonarrSeason]?
    var year: Int?
    var path: String?
    var rootFolderPath: String?
    var qualityProfileId: Int?
    var seasonFolder: Bool?
    var monitored: Bool = true
    var monitorNewItems: String?
    var runtime: Int?
    var tvdbId: Int?
    var tmdbId: Int?
    var imdbId: String?
    var titleSlug: String?
    var seriesType: String?
    var certification: String?
    var genres: [String]?
    var tags: [Int]?
    var added: Date?
    var ratings: SonarrRatings?
    var statistics: SonarrSeriesStatistics?
    var firstAired: Date?
    var lastAired: Date?
    var previousAiring: Date?
    var nextAiring: Date?
    var originalLanguage: ArrLanguage?

    var displayYear: String { year.map(String.init) ?? "—" }
    var isContinuing: Bool { (status ?? "").lowercased() == "continuing" }
    var completion: Double {
        guard let stats = statistics, let total = stats.episodeCount, total > 0 else { return 0 }
        return Double(stats.episodeFileCount ?? 0) / Double(total)
    }
    var missingCount: Int {
        guard let stats = statistics else { return 0 }
        return max(0, (stats.episodeCount ?? 0) - (stats.episodeFileCount ?? 0))
    }
    var sizeOnDisk: Int64 { statistics?.sizeOnDisk ?? 0 }
}

struct SonarrMediaInfo: Codable, Hashable {
    var audioCodec: String?
    var audioChannels: Double?
    var audioLanguages: String?
    var videoCodec: String?
    var videoDynamicRange: String?
    var resolution: String?
    var runTime: String?
    var subtitles: String?
    var videoBitDepth: Int?
}

struct SonarrEpisodeFile: Codable, Hashable, Identifiable {
    var id: Int
    var relativePath: String?
    var path: String?
    var size: Int64?
    var dateAdded: Date?
    var quality: ArrQuality?
    var mediaInfo: SonarrMediaInfo?
    var languages: [ArrLanguage]?
    var releaseGroup: String?
    var customFormatScore: Int?
}

struct SonarrEpisode: Codable, Identifiable, Hashable {
    var id: Int
    var seriesId: Int?
    var tvdbId: Int?
    var episodeFileId: Int?
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    var absoluteEpisodeNumber: Int?
    var title: String?
    var airDate: String?
    var airDateUtc: Date?
    var runtime: Int?
    var overview: String?
    var hasFile: Bool?
    var monitored: Bool?
    var finaleType: String?
    var episodeFile: SonarrEpisodeFile?
    var series: SonarrSeries?
    var grabbed: Bool?

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
    var hasAired: Bool {
        guard let air = airDateUtc else { return false }
        return air < Date()
    }
    var isMissing: Bool { (monitored ?? false) && !(hasFile ?? false) && hasAired }
}

struct SonarrQueueRecord: Codable, Identifiable, Hashable {
    var id: Int
    var seriesId: Int?
    var episodeId: Int?
    var seasonNumber: Int?
    var title: String?
    var status: String?
    var trackedDownloadStatus: String?
    var trackedDownloadState: String?
    var statusMessages: [ArrStatusMessage]?
    var errorMessage: String?
    var size: Double?
    var sizeleft: Double?
    var timeleft: String?
    var estimatedCompletionTime: Date?
    var added: Date?
    var downloadId: String?
    var `protocol`: String?
    var downloadClient: String?
    var indexer: String?
    var outputPath: String?
    var quality: ArrQuality?
    var series: SonarrSeries?
    var episode: SonarrEpisode?
    var languages: [ArrLanguage]?

    var progress: Double {
        guard let size, size > 0, let left = sizeleft else { return 0 }
        return max(0, min(1, (size - left) / size))
    }
    var label: String {
        if let series = series?.title, let ep = episode {
            return "\(series) · \(ep.code)"
        }
        return title ?? "Unknown"
    }
    var problem: String? {
        if let errorMessage, !errorMessage.isEmpty,
           (trackedDownloadStatus ?? "ok").lowercased() != "ok" { return errorMessage }
        let msgs = (statusMessages ?? []).flatMap { $0.messages ?? [] }
        return msgs.isEmpty ? nil : msgs.joined(separator: " ")
    }
}

struct SonarrHistoryRecord: Codable, Identifiable, Hashable {
    var id: Int
    var episodeId: Int?
    var seriesId: Int?
    var sourceTitle: String?
    var date: Date?
    var eventType: String?
    var quality: ArrQuality?
    var series: SonarrSeries?
    var episode: SonarrEpisode?
    var data: [String: JSONValue]?

    var reason: String? { data?["reason"]?.stringValue ?? data?["message"]?.stringValue }
    var indexer: String? { data?["indexer"]?.stringValue }
}

struct SonarrAddOptions: Codable {
    var monitor: String = "all"
    var searchForMissingEpisodes: Bool = true
    var searchForCutoffUnmetEpisodes: Bool = false
    var ignoreEpisodesWithFiles: Bool = false
    var ignoreEpisodesWithoutFiles: Bool = false
}

/// Payload for `POST /series`.
struct SonarrAddSeriesRequest: Encodable {
    var title: String
    var tvdbId: Int
    var titleSlug: String?
    var year: Int?
    var qualityProfileId: Int
    var rootFolderPath: String
    var monitored: Bool
    var seasonFolder: Bool
    var seriesType: String
    var monitorNewItems: String = "all"
    var languageProfileId: Int = 1
    var tags: [Int] = []
    var images: [ArrImage] = []
    var seasons: [SonarrSeason] = []
    var addOptions: SonarrAddOptions
}

enum SonarrMonitorStrategy: String, CaseIterable, Identifiable {
    case all, future, missing, existing, firstSeason, lastSeason, pilot, recent, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All episodes"
        case .future: return "Future episodes"
        case .missing: return "Missing episodes"
        case .existing: return "Existing episodes"
        case .firstSeason: return "First season"
        case .lastSeason: return "Last season"
        case .pilot: return "Pilot only"
        case .recent: return "Recent episodes"
        case .none: return "None"
        }
    }
}
