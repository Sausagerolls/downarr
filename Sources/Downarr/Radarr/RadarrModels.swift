import Foundation

/// Radarr exposes ratings as a dictionary of sources, unlike Sonarr's single value.
struct RadarrRatingValue: Codable, Hashable {
    var votes: Int?
    var value: Double?
    var type: String?
}

struct RadarrRatings: Codable, Hashable {
    var imdb: RadarrRatingValue?
    var tmdb: RadarrRatingValue?
    var metacritic: RadarrRatingValue?
    var rottenTomatoes: RadarrRatingValue?
    var trakt: RadarrRatingValue?

    var best: Double? { imdb?.value ?? tmdb?.value ?? trakt?.value }
}

struct RadarrMediaInfo: Codable, Hashable {
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

struct RadarrMovieFile: Codable, Hashable, Identifiable {
    var id: Int
    var relativePath: String?
    var path: String?
    var size: Int64?
    var dateAdded: Date?
    var quality: ArrQuality?
    var mediaInfo: RadarrMediaInfo?
    var languages: [ArrLanguage]?
    var releaseGroup: String?
    var edition: String?
    var customFormatScore: Int?
}

struct RadarrCollection: Codable, Hashable {
    var title: String?
    var tmdbId: Int?
}

struct RadarrMovie: Codable, Identifiable, Hashable {
    var id: Int?
    var title: String = ""
    var originalTitle: String?
    var sortTitle: String?
    var year: Int?
    var status: String?
    var overview: String?
    var studio: String?
    var runtime: Int?
    var path: String?
    var rootFolderPath: String?
    var folderName: String?
    var qualityProfileId: Int?
    var monitored: Bool = true
    var minimumAvailability: String?
    var isAvailable: Bool?
    var hasFile: Bool?
    var movieFileId: Int?
    var movieFile: RadarrMovieFile?
    var sizeOnDisk: Int64?
    var images: [ArrImage]?
    var genres: [String]?
    var tags: [Int]?
    var added: Date?
    var inCinemas: Date?
    var physicalRelease: Date?
    var digitalRelease: Date?
    var releaseDate: Date?
    var tmdbId: Int?
    var imdbId: String?
    var titleSlug: String?
    var certification: String?
    var website: String?
    var youTubeTrailerId: String?
    var popularity: Double?
    var ratings: RadarrRatings?
    var collection: RadarrCollection?
    var originalLanguage: ArrLanguage?

    var displayYear: String { year.map(String.init) ?? "—" }
    var qualityName: String? { movieFile?.quality?.quality?.name }
    var isMissing: Bool { monitored && !(hasFile ?? false) }
    var availabilityDate: Date? { digitalRelease ?? physicalRelease ?? inCinemas ?? releaseDate }
}

struct RadarrQueueRecord: Codable, Identifiable, Hashable {
    var id: Int
    var movieId: Int?
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
    var movie: RadarrMovie?
    var languages: [ArrLanguage]?

    var progress: Double {
        guard let size, size > 0, let left = sizeleft else { return 0 }
        return max(0, min(1, (size - left) / size))
    }
    var label: String { movie?.title ?? title ?? "Unknown" }
    var problem: String? {
        if let errorMessage, !errorMessage.isEmpty,
           (trackedDownloadStatus ?? "ok").lowercased() != "ok" { return errorMessage }
        let msgs = (statusMessages ?? []).flatMap { $0.messages ?? [] }
        return msgs.isEmpty ? nil : msgs.joined(separator: " ")
    }
}

struct RadarrHistoryRecord: Codable, Identifiable, Hashable {
    var id: Int
    var movieId: Int?
    var sourceTitle: String?
    var date: Date?
    var eventType: String?
    var quality: ArrQuality?
    var movie: RadarrMovie?
    var data: [String: JSONValue]?

    var reason: String? { data?["reason"]?.stringValue ?? data?["message"]?.stringValue }
    var indexer: String? { data?["indexer"]?.stringValue }
}

struct RadarrAddOptions: Codable {
    var searchForMovie: Bool = true
    var monitor: String = "movieOnly"
}

struct RadarrAddMovieRequest: Encodable {
    var title: String
    var tmdbId: Int
    var year: Int?
    var titleSlug: String?
    var qualityProfileId: Int
    var rootFolderPath: String
    var monitored: Bool
    var minimumAvailability: String
    var tags: [Int] = []
    var images: [ArrImage] = []
    var addOptions: RadarrAddOptions
}

enum RadarrAvailability: String, CaseIterable, Identifiable {
    case announced, inCinemas, released
    var id: String { rawValue }
    var label: String {
        switch self {
        case .announced: return "Announced"
        case .inCinemas: return "In cinemas"
        case .released: return "Released"
        }
    }
}
