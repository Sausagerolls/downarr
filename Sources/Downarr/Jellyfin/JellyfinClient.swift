import Foundation

/// Jellyfin management client (no playback). Handles the MediaBrowser auth header, item queries,
/// metadata writes, identify/fix-match and artwork.
struct JellyfinClient {
    let baseURL: URL
    let token: String
    let userID: String
    private let deviceID: String
    private let http: HTTPClient

    init(endpoint: ServiceEndpoint, token: String, userID: String, deviceID: String) throws {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("Jellyfin")
        }
        baseURL = base
        self.token = token
        self.userID = userID
        self.deviceID = deviceID.isEmpty ? "downarr" : deviceID
        http = HTTPClient(baseURL: base, basePath: "",
                          headers: ["Authorization": Self.authHeader(token: token, deviceID: deviceID)])
    }

    static func authHeader(token: String, deviceID: String) -> String {
        var parts = [
            "MediaBrowser Client=\"Downarr\"",
            "Device=\"Mac\"",
            "DeviceId=\"\(deviceID.isEmpty ? "downarr" : deviceID)\"",
            "Version=\"1.0\"",
        ]
        if !token.isEmpty { parts.append("Token=\"\(token)\"") }
        return parts.joined(separator: ", ")
    }

    /// Authenticate and return the new session. Static because it runs before a client exists.
    static func authenticate(endpoint: ServiceEndpoint, deviceID: String) async throws -> JellyfinAuthResult {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("Jellyfin")
        }
        struct Body: Encodable { var Username: String; var Pw: String }
        let client = HTTPClient(baseURL: base, basePath: "",
                                headers: ["Authorization": authHeader(token: "", deviceID: deviceID)])
        return try await client.post("/Users/AuthenticateByName",
                                     body: Body(Username: endpoint.username, Pw: endpoint.password))
    }

    // MARK: System
    func systemInfo() async throws -> JellyfinSystemInfo { try await http.get("/System/Info") }
    func counts() async throws -> JellyfinItemCounts { try await http.get("/Items/Counts") }
    func virtualFolders() async throws -> [JellyfinVirtualFolder] { try await http.get("/Library/VirtualFolders") }
    func views() async throws -> JellyfinItemsResponse { try await http.get("/Users/\(userID)/Views") }
    func scheduledTasks() async throws -> [JellyfinScheduledTask] { try await http.get("/ScheduledTasks") }

    func runTask(id: String) async throws {
        _ = try await http.postVoid("/ScheduledTasks/Running/\(id)")
    }

    func scanAllLibraries() async throws {
        _ = try await http.postVoid("/Library/Refresh")
    }

    // MARK: Items

    static let itemFields = [
        "Overview", "Genres", "GenreItems", "Studios", "ProviderIds", "Path", "DateCreated",
        "People", "Taglines", "Tags", "ProductionYear", "PremiereDate", "OfficialRating",
        "CommunityRating", "CriticRating", "SortName", "OriginalTitle", "ChildCount",
        "RecursiveItemCount", "MediaSources", "MediaStreams", "ProductionLocations", "Status",
    ].joined(separator: ",")

    struct ItemQuery {
        var parentID: String?
        var includeTypes: [String] = []
        var recursive = true
        var startIndex = 0
        var limit = 100
        var sortBy = "SortName"
        var sortOrder = "Ascending"
        var searchTerm: String?
        var nameStartsWith: String?
        var filters: [String] = []
        var genres: [String] = []
        var years: [Int] = []
    }

    func items(_ query: ItemQuery) async throws -> JellyfinItemsResponse {
        var q: [String: String?] = [
            "userId": userID,
            "Recursive": query.recursive ? "true" : "false",
            "StartIndex": String(query.startIndex),
            "Limit": String(query.limit),
            "SortBy": query.sortBy,
            "SortOrder": query.sortOrder,
            "Fields": Self.itemFields,
            "ImageTypeLimit": "1",
            "EnableTotalRecordCount": "true",
        ]
        if let parent = query.parentID { q["ParentId"] = parent }
        if !query.includeTypes.isEmpty { q["IncludeItemTypes"] = query.includeTypes.joined(separator: ",") }
        if let term = query.searchTerm, !term.isEmpty { q["SearchTerm"] = term }
        if let prefix = query.nameStartsWith, !prefix.isEmpty { q["NameStartsWith"] = prefix }
        if !query.filters.isEmpty { q["Filters"] = query.filters.joined(separator: ",") }
        if !query.genres.isEmpty { q["Genres"] = query.genres.joined(separator: "|") }
        if !query.years.isEmpty { q["Years"] = query.years.map(String.init).joined(separator: ",") }
        return try await http.get("/Items", query: q)
    }

    func item(id: String) async throws -> JellyfinItem {
        try await http.get("/Items/\(id)", query: ["userId": userID, "Fields": Self.itemFields])
    }

    func latest(parentID: String?, limit: Int = 20) async throws -> [JellyfinItem] {
        var q: [String: String?] = [
            "userId": userID,
            "Limit": String(limit),
            "Fields": Self.itemFields,
            "EnableImages": "true",
        ]
        if let parentID { q["ParentId"] = parentID }
        return try await http.get("/Items/Latest", query: q)
    }

    func seasons(seriesID: String) async throws -> JellyfinItemsResponse {
        try await http.get("/Shows/\(seriesID)/Seasons",
                           query: ["userId": userID, "Fields": Self.itemFields])
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> JellyfinItemsResponse {
        var q: [String: String?] = ["userId": userID, "Fields": Self.itemFields]
        if let seasonID { q["seasonId"] = seasonID }
        return try await http.get("/Shows/\(seriesID)/Episodes", query: q)
    }

    func deleteItem(id: String) async throws {
        try await http.delete("/Items/\(id)")
    }

    // MARK: Metadata editing

    func metadataEditorInfo(id: String) async throws -> JellyfinMetadataEditorInfo {
        try await http.get("/Items/\(id)/MetadataEditor")
    }

    /// Fetch the raw DTO so edits preserve every field Jellyfin sends back.
    func rawItem(id: String) async throws -> [String: JSONValue] {
        let data = try await http.data("GET", "/Items/\(id)", query: ["userId": userID])
        guard let object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue else {
            throw APIError.decoding("item \(id) was not a JSON object")
        }
        return object
    }

    /// `POST /Items/{id}` replaces the whole DTO, so callers patch the raw object.
    func updateItem(id: String, changes: [String: JSONValue]) async throws {
        var object = try await rawItem(id: id)
        for (key, value) in changes { object[key] = value }
        let body = try Coders.encoder.encode(JSONValue.object(object))
        _ = try await http.data("POST", "/Items/\(id)", body: body)
    }

    func refreshItem(id: String,
                     metadata: JellyfinRefreshMode,
                     images: JellyfinRefreshMode,
                     replaceMetadata: Bool,
                     replaceImages: Bool,
                     recursive: Bool = false) async throws {
        _ = try await http.postVoid("/Items/\(id)/Refresh", query: [
            "metadataRefreshMode": metadata.rawValue,
            "imageRefreshMode": images.rawValue,
            "replaceAllMetadata": replaceMetadata ? "true" : "false",
            "replaceAllImages": replaceImages ? "true" : "false",
            "recursive": recursive ? "true" : "false",
        ])
    }

    // MARK: Identify / fix match

    struct RemoteSearchQuery: Encodable {
        struct SearchInfo: Encodable {
            var Name: String?
            var Year: Int?
            var IndexNumber: Int?
            var ParentIndexNumber: Int?
            var ProviderIds: [String: String]?
            var PremiereDate: String?
            var MetadataLanguage: String?
            var MetadataCountryCode: String?
        }
        var ItemId: String
        var SearchInfo: SearchInfo
        var IncludeDisabledProviders = true
    }

    func remoteSearch(kind: JellyfinItemKind, query: RemoteSearchQuery) async throws -> [JellyfinRemoteSearchResult] {
        guard let path = kind.remoteSearchPath else {
            throw APIError.notConfigured("Identify for \(kind.rawValue)")
        }
        return try await http.post("/Items/RemoteSearch/\(path)", body: query)
    }

    func applyRemoteSearch(id: String, result: JellyfinRemoteSearchResult, replaceAllImages: Bool) async throws {
        struct Body: Encodable {
            var Name: String?
            var ProductionYear: Int?
            var IndexNumber: Int?
            var ParentIndexNumber: Int?
            var ProviderIds: [String: String]?
            var SearchProviderName: String?
            var ImageUrl: String?
            var Overview: String?
        }
        let body = Body(Name: result.Name,
                        ProductionYear: result.ProductionYear,
                        IndexNumber: result.IndexNumber,
                        ParentIndexNumber: result.ParentIndexNumber,
                        ProviderIds: result.ProviderIds,
                        SearchProviderName: result.SearchProviderName,
                        ImageUrl: result.ImageUrl,
                        Overview: result.Overview)
        _ = try await http.postVoid("/Items/RemoteSearch/Apply/\(id)",
                                     query: ["replaceAllImages": replaceAllImages ? "true" : "false"],
                                     body: body)
    }

    // MARK: Images

    func images(id: String) async throws -> [JellyfinImageInfo] {
        try await http.get("/Items/\(id)/Images")
    }

    func remoteImages(id: String, type: String, provider: String?,
                      includeAllLanguages: Bool, startIndex: Int = 0,
                      limit: Int = 40) async throws -> JellyfinRemoteImagesResponse {
        try await http.get("/Items/\(id)/RemoteImages", query: [
            "type": type,
            "providerName": provider,
            "includeAllLanguages": includeAllLanguages ? "true" : "false",
            "startIndex": String(startIndex),
            "limit": String(limit),
        ])
    }

    func downloadRemoteImage(id: String, type: String, url: String) async throws {
        _ = try await http.postVoid("/Items/\(id)/RemoteImages/Download",
                                     query: ["type": type, "imageUrl": url])
    }

    func deleteImage(id: String, type: String, index: Int?) async throws {
        try await http.delete("/Items/\(id)/Images/\(type)",
                              query: index.map { ["imageIndex": String($0)] } ?? [:])
    }

    /// Jellyfin expects the raw bytes base64-encoded as the request body.
    func uploadImage(id: String, type: String, data: Data, mimeType: String) async throws {
        let encoded = data.base64EncodedString()
        _ = try await http.data("POST", "/Items/\(id)/Images/\(type)",
                                body: Data(encoded.utf8), contentType: mimeType)
    }

    // MARK: Image URLs

    func imageURL(itemID: String, type: String = "Primary", tag: String? = nil,
                  maxHeight: Int? = 600, index: Int? = nil) -> URL? {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var path = "/Items/\(itemID)/Images/\(type)"
        if let index { path += "/\(index)" }
        comps?.path = path
        var items = [URLQueryItem(name: "api_key", value: token)]
        if let tag { items.append(URLQueryItem(name: "tag", value: tag)) }
        if let maxHeight { items.append(URLQueryItem(name: "fillHeight", value: String(maxHeight))) }
        items.append(URLQueryItem(name: "quality", value: "90"))
        comps?.queryItems = items
        return comps?.url
    }

    func posterURL(_ item: JellyfinItem, maxHeight: Int = 450) -> URL? {
        if let tag = item.ImageTags?["Primary"] {
            return imageURL(itemID: item.Id, type: "Primary", tag: tag, maxHeight: maxHeight)
        }
        // Episodes and seasons often only have artwork on the parent.
        if item.kind == .episode, let seriesID = item.SeriesId {
            return imageURL(itemID: seriesID, type: "Primary", tag: nil, maxHeight: maxHeight)
        }
        return nil
    }

    func backdropURL(_ item: JellyfinItem, maxHeight: Int = 720) -> URL? {
        if item.BackdropImageTags?.isEmpty == false {
            return imageURL(itemID: item.Id, type: "Backdrop", tag: item.BackdropImageTags?.first,
                            maxHeight: maxHeight, index: 0)
        }
        if let seriesID = item.SeriesId {
            return imageURL(itemID: seriesID, type: "Backdrop", tag: nil, maxHeight: maxHeight, index: 0)
        }
        if let thumb = item.ImageTags?["Thumb"] {
            return imageURL(itemID: item.Id, type: "Thumb", tag: thumb, maxHeight: maxHeight)
        }
        return nil
    }
}
