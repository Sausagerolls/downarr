import Foundation

/// Radarr v3 API. Mirrors `SonarrClient`, including the raw-JSON patch strategy for writes.
struct RadarrClient {
    let http: HTTPClient
    let images: ArrImageResolver

    init(endpoint: ServiceEndpoint) throws {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("Radarr")
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
    func movies() async throws -> [RadarrMovie] { try await http.get("/movie") }
    func movie(id: Int) async throws -> RadarrMovie { try await http.get("/movie/\(id)") }

    func lookup(_ term: String) async throws -> [RadarrMovie] {
        try await http.get("/movie/lookup", query: ["term": term])
    }

    func addMovie(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
        try await http.post("/movie", body: request)
    }

    func deleteMovie(id: Int, deleteFiles: Bool, addExclusion: Bool) async throws {
        try await http.delete("/movie/\(id)", query: [
            "deleteFiles": deleteFiles ? "true" : "false",
            "addImportExclusion": addExclusion ? "true" : "false",
        ])
    }

    func patchMovie(id: Int, changes: [String: JSONValue]) async throws -> RadarrMovie {
        let data = try await http.data("GET", "/movie/\(id)")
        guard var object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue else {
            throw APIError.decoding("movie \(id) was not a JSON object")
        }
        for (key, value) in changes { object[key] = value }
        let body = try Coders.encoder.encode(JSONValue.object(object))
        let updated = try await http.data("PUT", "/movie/\(id)", body: body)
        return try Coders.decoder.decode(RadarrMovie.self, from: updated)
    }

    func deleteMovieFile(id: Int) async throws {
        try await http.delete("/moviefile/\(id)")
    }

    // MARK: Activity
    func queue(pageSize: Int = 200) async throws -> ArrPage<RadarrQueueRecord> {
        try await http.get("/queue", query: [
            "pageSize": String(pageSize),
            "includeMovie": "true",
            "includeUnknownMovieItems": "true",
        ])
    }

    func removeFromQueue(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
        try await http.delete("/queue/\(id)", query: [
            "removeFromClient": removeFromClient ? "true" : "false",
            "blocklist": blocklist ? "true" : "false",
            "skipRedownload": "false",
        ])
    }

    func missing(page: Int = 1, pageSize: Int = 100) async throws -> ArrPage<RadarrMovie> {
        try await http.get("/wanted/missing", query: [
            "page": String(page),
            "pageSize": String(pageSize),
            "sortKey": "digitalRelease",
            "sortDirection": "descending",
            "monitored": "true",
        ])
    }

    func history(page: Int = 1, pageSize: Int = 60) async throws -> ArrPage<RadarrHistoryRecord> {
        try await http.get("/history", query: [
            "page": String(page),
            "pageSize": String(pageSize),
            "includeMovie": "true",
        ])
    }

    func calendar(start: Date, end: Date) async throws -> [RadarrMovie] {
        try await http.get("/calendar", query: [
            "start": Coders.iso8601.string(from: start),
            "end": Coders.iso8601.string(from: end),
            "unmonitored": "false",
        ])
    }

    // MARK: Search
    func releases(movieID: Int) async throws -> [ArrRelease] {
        try await http.get("/release", query: ["movieId": String(movieID)])
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

    func searchMovies(_ ids: [Int]) async throws {
        try await command(ArrCommand("MoviesSearch", [
            "movieIds": .array(ids.map { .number(Double($0)) }),
        ]))
    }

    func refresh(movieID: Int) async throws {
        try await command(ArrCommand("RefreshMovie", [
            "movieIds": .array([.number(Double(movieID))]),
        ]))
    }

    func rescan(movieID: Int) async throws {
        try await command(ArrCommand("RescanMovie", [
            "movieIds": .array([.number(Double(movieID))]),
        ]))
    }

    func renameFiles(movieID: Int) async throws {
        try await command(ArrCommand("RenameMovie", [
            "movieIds": .array([.number(Double(movieID))]),
        ]))
    }
}
