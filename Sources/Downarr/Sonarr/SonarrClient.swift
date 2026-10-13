import Foundation

/// Sonarr v3 API. Reads use typed models; writes that must preserve server-side fields
/// round-trip the raw JSON object (see `patchSeries`).
struct SonarrClient {
    let http: HTTPClient
    let images: ArrImageResolver

    init(endpoint: ServiceEndpoint) throws {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("Sonarr")
        }
        http = HTTPClient(baseURL: base,
                          basePath: "/api/v3",
                          headers: ["X-Api-Key": endpoint.apiKey])
        images = ArrImageResolver(baseURL: base, apiKey: endpoint.apiKey)
    }

    // MARK: System
    func status() async throws -> ArrSystemStatus { try await http.get("/system/status") }
    func health() async throws -> [ArrHealth] { try await http.get("/health") }
    func diskSpace() async throws -> [ArrDiskSpace] { try await http.get("/diskspace") }
    func qualityProfiles() async throws -> [ArrQualityProfile] { try await http.get("/qualityprofile") }
    func rootFolders() async throws -> [ArrRootFolder] { try await http.get("/rootfolder") }
    func tags() async throws -> [ArrTag] { try await http.get("/tag") }

    // MARK: Library
    func series() async throws -> [SonarrSeries] { try await http.get("/series") }

    func series(id: Int) async throws -> SonarrSeries { try await http.get("/series/\(id)") }

    func lookup(_ term: String) async throws -> [SonarrSeries] {
        try await http.get("/series/lookup", query: ["term": term])
    }

    func addSeries(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
        try await http.post("/series", body: request)
    }

    func deleteSeries(id: Int, deleteFiles: Bool, addExclusion: Bool) async throws {
        try await http.delete("/series/\(id)", query: [
            "deleteFiles": deleteFiles ? "true" : "false",
            "addImportListExclusion": addExclusion ? "true" : "false",
        ])
    }

    /// Fetch the full raw series object, apply `changes`, PUT it back.
    /// Sonarr replaces the whole document on PUT, so anything we don't model must survive.
    func patchSeries(id: Int, changes: [String: JSONValue]) async throws -> SonarrSeries {
        let data = try await http.data("GET", "/series/\(id)")
        guard var object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue else {
            throw APIError.decoding("series \(id) was not a JSON object")
        }
        for (key, value) in changes { object[key] = value }
        let body = try Coders.encoder.encode(JSONValue.object(object))
        let updated = try await http.data("PUT", "/series/\(id)", body: body)
        return try Coders.decoder.decode(SonarrSeries.self, from: updated)
    }

    /// Season monitoring lives inside the series document.
    func setSeasonMonitored(seriesID: Int, seasonNumber: Int, monitored: Bool) async throws -> SonarrSeries {
        let data = try await http.data("GET", "/series/\(seriesID)")
        guard var object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue,
              var seasons = object["seasons"]?.arrayValue else {
            throw APIError.decoding("series \(seriesID) has no seasons array")
        }
        seasons = seasons.map { season in
            guard var dict = season.objectValue,
                  dict["seasonNumber"]?.intValue == seasonNumber else { return season }
            dict["monitored"] = .bool(monitored)
            return .object(dict)
        }
        object["seasons"] = .array(seasons)
        let body = try Coders.encoder.encode(JSONValue.object(object))
        let updated = try await http.data("PUT", "/series/\(seriesID)", body: body)
        return try Coders.decoder.decode(SonarrSeries.self, from: updated)
    }

    // MARK: Episodes
    func episodes(seriesID: Int) async throws -> [SonarrEpisode] {
        try await http.get("/episode", query: ["seriesId": String(seriesID)])
    }

    func setEpisodesMonitored(ids: [Int], monitored: Bool) async throws {
        struct Body: Encodable { var episodeIds: [Int]; var monitored: Bool }
        _ = try await http.data("PUT", "/episode/monitor",
                                body: try Coders.encoder.encode(Body(episodeIds: ids, monitored: monitored)))
    }

    func deleteEpisodeFile(id: Int) async throws {
        try await http.delete("/episodefile/\(id)")
    }

    // MARK: Activity
    func queue(pageSize: Int = 200) async throws -> ArrPage<SonarrQueueRecord> {
        try await http.get("/queue", query: [
            "pageSize": String(pageSize),
            "includeSeries": "true",
            "includeEpisode": "true",
            "includeUnknownSeriesItems": "true",
        ])
    }

    func removeFromQueue(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
        try await http.delete("/queue/\(id)", query: [
            "removeFromClient": removeFromClient ? "true" : "false",
            "blocklist": blocklist ? "true" : "false",
            "skipRedownload": "false",
        ])
    }

    func missing(page: Int = 1, pageSize: Int = 100) async throws -> ArrPage<SonarrEpisode> {
        try await http.get("/wanted/missing", query: [
            "page": String(page),
            "pageSize": String(pageSize),
            "sortKey": "airDateUtc",
            "sortDirection": "descending",
            "includeSeries": "true",
            "monitored": "true",
        ])
    }

    func history(page: Int = 1, pageSize: Int = 60) async throws -> ArrPage<SonarrHistoryRecord> {
        try await http.get("/history", query: [
            "page": String(page),
            "pageSize": String(pageSize),
            "includeSeries": "true",
            "includeEpisode": "true",
        ])
    }

    func calendar(start: Date, end: Date) async throws -> [SonarrEpisode] {
        try await http.get("/calendar", query: [
            "start": Coders.iso8601.string(from: start),
            "end": Coders.iso8601.string(from: end),
            "includeSeries": "true",
            "unmonitored": "false",
        ])
    }

    // MARK: Search
    func releases(episodeID: Int) async throws -> [ArrRelease] {
        try await http.get("/release", query: ["episodeId": String(episodeID)])
    }

    func releases(seriesID: Int, seasonNumber: Int) async throws -> [ArrRelease] {
        try await http.get("/release", query: [
            "seriesId": String(seriesID),
            "seasonNumber": String(seasonNumber),
        ])
    }

    func grab(_ release: ArrRelease) async throws {
        guard let guid = release.guid, let indexerId = release.indexerId else {
            throw APIError.notConfigured("release")
        }
        _ = try await http.postVoid("/release", body: ArrGrabRequest(guid: guid, indexerId: indexerId))
    }

    @discardableResult
    func command(_ command: ArrCommand) async throws -> ArrCommandResult {
        try await http.post("/command", body: command)
    }

    func searchSeries(_ id: Int) async throws {
        try await command(ArrCommand("SeriesSearch", ["seriesId": .number(Double(id))]))
    }

    func searchSeason(seriesID: Int, seasonNumber: Int) async throws {
        try await command(ArrCommand("SeasonSearch", [
            "seriesId": .number(Double(seriesID)),
            "seasonNumber": .number(Double(seasonNumber)),
        ]))
    }

    func searchEpisodes(_ ids: [Int]) async throws {
        try await command(ArrCommand("EpisodeSearch", [
            "episodeIds": .array(ids.map { .number(Double($0)) }),
        ]))
    }

    func refresh(seriesID: Int) async throws {
        try await command(ArrCommand("RefreshSeries", ["seriesId": .number(Double(seriesID))]))
    }

    func rescan(seriesID: Int) async throws {
        try await command(ArrCommand("RescanSeries", ["seriesId": .number(Double(seriesID))]))
    }

    func renameFiles(seriesID: Int) async throws {
        try await command(ArrCommand("RenameSeries", [
            "seriesIds": .array([.number(Double(seriesID))]),
        ]))
    }
}
