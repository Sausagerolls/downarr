import Foundation
import SwiftUI

// Sonarr and Radarr are both Servarr apps: images, qualities, profiles, root folders, releases,
// commands, health and paging are byte-identical between them, so those live here once.

struct ArrImage: Codable, Hashable {
    var coverType: String?
    var url: String?
    var remoteUrl: String?
}

struct ArrQualityItem: Codable, Hashable {
    var id: Int?
    var name: String?
    var source: String?
    var resolution: Int?
}

struct ArrRevision: Codable, Hashable {
    var version: Int?
    var real: Int?
    var isRepack: Bool?
}

struct ArrQuality: Codable, Hashable {
    var quality: ArrQualityItem?
    var revision: ArrRevision?

    var name: String { quality?.name ?? "Unknown" }
}

struct ArrLanguage: Codable, Hashable, Identifiable {
    var id: Int?
    var name: String?
}

struct ArrQualityProfile: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var upgradeAllowed: Bool?
}

struct ArrRootFolder: Codable, Identifiable, Hashable {
    var id: Int
    var path: String
    var freeSpace: Int64?
    var accessible: Bool?
}

struct ArrTag: Codable, Identifiable, Hashable {
    var id: Int
    var label: String
}

struct ArrDiskSpace: Codable, Hashable, Identifiable {
    var path: String
    var label: String?
    var freeSpace: Int64?
    var totalSpace: Int64?

    var id: String { path }
    var usedFraction: Double {
        guard let total = totalSpace, total > 0, let free = freeSpace else { return 0 }
        return Double(total - free) / Double(total)
    }
}

struct ArrSystemStatus: Codable, Hashable {
    var appName: String?
    var version: String?
    var osName: String?
    var isDocker: Bool?
    var startTime: Date?
    var instanceName: String?
}

struct ArrHealth: Codable, Hashable, Identifiable {
    var source: String?
    var type: String?
    var message: String?
    var wikiUrl: String?

    var id: String { (source ?? "") + (message ?? "") }
    var isError: Bool { (type ?? "").lowercased() == "error" }
}

struct ArrPage<T: Codable>: Codable {
    var page: Int?
    var pageSize: Int?
    var totalRecords: Int?
    var records: [T]?
}

struct ArrStatusMessage: Codable, Hashable {
    var title: String?
    var messages: [String]?
}

struct ArrRelease: Codable, Identifiable, Hashable {
    var guid: String?
    var title: String?
    var indexer: String?
    var indexerId: Int?
    var size: Int64?
    var age: Int?
    var ageHours: Double?
    var seeders: Int?
    var leechers: Int?
    var quality: ArrQuality?
    var rejected: Bool?
    var rejections: [String]?
    var `protocol`: String?
    var publishDate: Date?
    var downloadUrl: String?
    var customFormatScore: Int?
    var languages: [ArrLanguage]?
    var fullSeason: Bool?
    var seasonNumber: Int?
    var episodeNumbers: [Int]?
    var downloadAllowed: Bool?
    var releaseWeight: Int?

    var id: String { (guid ?? "") + (title ?? "") }
    var isUsenet: Bool { (`protocol` ?? "").lowercased().contains("usenet") }
}

/// Body for `POST /release` (grab a specific release).
struct ArrGrabRequest: Encodable {
    var guid: String
    var indexerId: Int
}

/// Body for `POST /command`. Servarr commands are `{name: …}` plus arbitrary extras.
struct ArrCommand: Encodable {
    var name: String
    var extras: [String: JSONValue] = [:]

    init(_ name: String, _ extras: [String: JSONValue] = [:]) {
        self.name = name
        self.extras = extras
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(name, forKey: DynamicKey(stringValue: "name"))
        for (key, value) in extras {
            try c.encode(value, forKey: DynamicKey(stringValue: key))
        }
    }
}

struct ArrCommandResult: Codable {
    var id: Int?
    var name: String?
    var status: String?
    var message: String?
}

/// Shared helpers for turning a Servarr media-cover path into a fetchable URL.
struct ArrImageResolver {
    let baseURL: URL
    let apiKey: String

    func url(_ images: [ArrImage]?, type: String) -> URL? {
        guard let images else { return nil }
        let match = images.first { ($0.coverType ?? "").lowercased() == type.lowercased() }
        guard let match else { return nil }
        if let raw = match.url, let comps = URLComponents(string: raw) {
            if comps.host == nil {
                // Server-relative: /MediaCover/12/poster.jpg?lastWrite=…
                var full = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
                full.path = comps.path
                var items = comps.queryItems ?? []
                items.append(URLQueryItem(name: "apikey", value: apiKey))
                full.queryItems = items
                return full.url
            }
            return comps.url
        }
        if let remote = match.remoteUrl { return URL(string: remote) }
        return nil
    }

    /// Lookup results only carry `remoteUrl`.
    func remoteURL(_ images: [ArrImage]?, type: String) -> URL? {
        guard let match = images?.first(where: { ($0.coverType ?? "").lowercased() == type.lowercased() }),
              let remote = match.remoteUrl else { return url(images, type: type) }
        return URL(string: remote)
    }
}

// MARK: - Presentation helpers shared by both libraries

enum ArrMonitorFilter: String, CaseIterable, Identifiable {
    case all, monitored, unmonitored, missing, complete
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .monitored: return "Monitored"
        case .unmonitored: return "Unmonitored"
        case .missing: return "Missing"
        case .complete: return "Complete"
        }
    }
}

enum ArrSortKey: String, CaseIterable, Identifiable {
    case title, added, year, size, progress, rating
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return "Title"
        case .added: return "Date added"
        case .year: return "Year"
        case .size: return "Size on disk"
        case .progress: return "Completion"
        case .rating: return "Rating"
        }
    }
}

func arrTrackedStateColor(_ state: String?) -> Color {
    switch (state ?? "").lowercased() {
    case "downloading", "importpending", "importing": return Theme.sonarr
    case "imported", "completed": return Theme.positive
    case "importblocked", "importfailed", "failedpending", "failed", "warning", "error":
        return Theme.danger
    case "ignored": return Theme.neutral
    default: return Theme.warning
    }
}
