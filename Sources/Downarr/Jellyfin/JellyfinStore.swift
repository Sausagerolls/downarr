import AppKit
import SwiftUI

@MainActor
final class JellyfinStore: ObservableObject {
    @Published private(set) var systemInfo: JellyfinSystemInfo?
    @Published private(set) var counts: JellyfinItemCounts?
    @Published private(set) var libraries: [JellyfinVirtualFolder] = []
    @Published private(set) var views: [JellyfinItem] = []
    @Published private(set) var tasks: [JellyfinScheduledTask] = []
    @Published private(set) var latest: [JellyfinItem] = []

    // Browser state
    @Published private(set) var items: [JellyfinItem] = []
    @Published private(set) var totalItems: Int = 0
    @Published var selectedLibraryID: String?
    @Published var typeFilter: JellyfinBrowseType = .auto
    @Published var sortBy: JellyfinSortOption = .sortName
    @Published var sortAscending = true
    @Published var searchText = ""

    @Published var connectionState: LoadState = .idle
    @Published var browseState: LoadState = .idle
    @Published var lastError: String?
    @Published var busy: Set<String> = []

    private(set) var client: JellyfinClient?
    private let toasts: ToastCenter
    private let config: ConfigStore
    private var loadMoreTask: Task<Void, Never>?

    init(toasts: ToastCenter, config: ConfigStore) {
        self.toasts = toasts
        self.config = config
    }

    var isConfigured: Bool { client != nil }
    var isAuthenticated: Bool { !(client?.token.isEmpty ?? true) }

    func configure(_ endpoint: ServiceEndpoint) {
        let c = config.config
        client = try? JellyfinClient(endpoint: endpoint,
                                     token: c.jellyfinToken,
                                     userID: c.jellyfinUserID,
                                     deviceID: c.jellyfinDeviceID)
    }

    // MARK: Auth

    @discardableResult
    func authenticate() async -> Bool {
        let endpoint = config.config.jellyfin
        connectionState = .loading
        do {
            let result = try await JellyfinClient.authenticate(endpoint: endpoint,
                                                               deviceID: config.config.jellyfinDeviceID)
            guard let token = result.AccessToken, let user = result.User else {
                throw APIError.transport("Jellyfin did not return a session token")
            }
            config.config.jellyfinToken = token
            config.config.jellyfinUserID = user.Id
            configure(endpoint)
            connectionState = .loaded
            lastError = nil
            return true
        } catch {
            let message = errorText(error)
            connectionState = .failed(message)
            lastError = message
            toasts.error("Jellyfin sign-in failed: \(message)")
            return false
        }
    }

    /// Runs `work`, re-authenticating once if the token has expired.
    private func withAuth<T>(_ work: (JellyfinClient) async throws -> T) async throws -> T {
        if client == nil || !isAuthenticated {
            guard await authenticate(), let client else {
                throw APIError.notConfigured("Jellyfin")
            }
            return try await work(client)
        }
        guard let client else { throw APIError.notConfigured("Jellyfin") }
        do {
            return try await work(client)
        } catch let error as APIError where error.isUnauthorized {
            guard await authenticate(), let refreshed = self.client else { throw error }
            return try await work(refreshed)
        }
    }

    // MARK: Loading

    func loadOverview(force: Bool = false) async {
        if !force, case .loaded = connectionState, !libraries.isEmpty { return }
        do {
            let info: JellyfinSystemInfo = try await withAuth { try await $0.systemInfo() }
            systemInfo = info
            connectionState = .loaded
            counts = try? await withAuth { try await $0.counts() }
            libraries = (try? await withAuth { try await $0.virtualFolders() }) ?? []
            views = (try? await withAuth { try await $0.views() })?.Items ?? []
            tasks = (try? await withAuth { try await $0.scheduledTasks() }) ?? []
            latest = (try? await withAuth { try await $0.latest(parentID: nil, limit: 24) }) ?? []
            lastError = nil
        } catch {
            connectionState = .failed(errorText(error))
            lastError = errorText(error)
        }
    }

    func library(id: String?) -> JellyfinVirtualFolder? {
        libraries.first { $0.ItemId == id }
    }

    var selectedLibrary: JellyfinVirtualFolder? { library(id: selectedLibraryID) }

    /// Item types to request, honouring the library's own collection type when set to `.auto`.
    private func includeTypes() -> [String] {
        if typeFilter != .auto { return typeFilter.itemTypes }
        switch selectedLibrary?.CollectionType {
        case "movies": return ["Movie"]
        case "tvshows": return ["Series"]
        case "music": return ["MusicAlbum"]
        default: return []
        }
    }

    func loadItems(reset: Bool = true) async {
        loadMoreTask?.cancel()
        if reset {
            items = []
            totalItems = 0
        }
        browseState = .loading
        var query = JellyfinClient.ItemQuery()
        query.parentID = selectedLibraryID
        query.includeTypes = includeTypes()
        query.startIndex = 0
        query.limit = 120
        query.sortBy = sortBy.rawValue
        query.sortOrder = sortAscending ? "Ascending" : "Descending"
        query.searchTerm = searchText.isEmpty ? nil : searchText
        do {
            let response = try await withAuth { try await $0.items(query) }
            items = response.Items ?? []
            totalItems = response.TotalRecordCount ?? items.count
            browseState = .loaded
            lastError = nil
        } catch {
            browseState = .failed(errorText(error))
            lastError = errorText(error)
        }
    }

    func loadMoreIfNeeded(currentItem: JellyfinItem) {
        guard items.count < totalItems,
              let index = items.firstIndex(where: { $0.Id == currentItem.Id }),
              index >= items.count - 24,
              loadMoreTask == nil || loadMoreTask?.isCancelled == true else { return }
        let startIndex = items.count
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            var query = JellyfinClient.ItemQuery()
            query.parentID = self.selectedLibraryID
            query.includeTypes = self.includeTypes()
            query.startIndex = startIndex
            query.limit = 120
            query.sortBy = self.sortBy.rawValue
            query.sortOrder = self.sortAscending ? "Ascending" : "Descending"
            query.searchTerm = self.searchText.isEmpty ? nil : self.searchText
            if let response = try? await self.withAuth({ try await $0.items(query) }) {
                let existing = Set(self.items.map(\.Id))
                self.items.append(contentsOf: (response.Items ?? []).filter { !existing.contains($0.Id) })
            }
            self.loadMoreTask = nil
        }
    }

    func item(id: String) async -> JellyfinItem? {
        do { return try await withAuth { try await $0.item(id: id) } }
        catch { report(error); return nil }
    }

    func seasons(seriesID: String) async -> [JellyfinItem] {
        do { return try await withAuth { try await $0.seasons(seriesID: seriesID) }.Items ?? [] }
        catch { report(error); return [] }
    }

    func episodes(seriesID: String, seasonID: String?) async -> [JellyfinItem] {
        do { return try await withAuth { try await $0.episodes(seriesID: seriesID, seasonID: seasonID) }.Items ?? [] }
        catch { report(error); return [] }
    }

    func children(parentID: String, types: [String] = []) async -> [JellyfinItem] {
        var query = JellyfinClient.ItemQuery()
        query.parentID = parentID
        query.includeTypes = types
        query.recursive = false
        query.limit = 500
        query.sortBy = "SortName"
        do { return try await withAuth { try await $0.items(query) }.Items ?? [] }
        catch { report(error); return [] }
    }

    func metadataEditorInfo(id: String) async -> JellyfinMetadataEditorInfo? {
        do { return try await withAuth { try await $0.metadataEditorInfo(id: id) } }
        catch { return nil }
    }

    // MARK: Images

    func posterURL(_ item: JellyfinItem, maxHeight: Int = 450) -> URL? {
        client?.posterURL(item, maxHeight: maxHeight)
    }

    func backdropURL(_ item: JellyfinItem) -> URL? { client?.backdropURL(item) }

    func imageURL(itemID: String, type: String, index: Int? = nil, maxHeight: Int? = 400) -> URL? {
        // A cache-busting token keeps replaced artwork from showing the previous bytes.
        client?.imageURL(itemID: itemID, type: type, tag: nil, maxHeight: maxHeight, index: index)
    }

    func images(itemID: String) async -> [JellyfinImageInfo] {
        do { return try await withAuth { try await $0.images(id: itemID) } }
        catch { report(error); return [] }
    }

    func remoteImages(itemID: String, type: String, provider: String?,
                      allLanguages: Bool) async -> JellyfinRemoteImagesResponse? {
        do {
            return try await withAuth {
                try await $0.remoteImages(id: itemID, type: type, provider: provider,
                                          includeAllLanguages: allLanguages, limit: 60)
            }
        } catch {
            report(error)
            return nil
        }
    }

    func applyRemoteImage(itemID: String, type: String, url: String) async -> Bool {
        await perform("image-\(type)") { client in
            try await client.downloadRemoteImage(id: itemID, type: type, url: url)
            self.toasts.success("\(type) image updated")
        }
    }

    func deleteImage(itemID: String, type: String, index: Int?) async -> Bool {
        await perform("image-del-\(type)") { client in
            try await client.deleteImage(id: itemID, type: type, index: index)
            self.toasts.success("\(type) image removed")
        }
    }

    func uploadImage(itemID: String, type: String, fileURL: URL) async -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else {
            toasts.error("Could not read \(fileURL.lastPathComponent)")
            return false
        }
        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "webp": mime = "image/webp"
        default: mime = "image/jpeg"
        }
        return await perform("image-up-\(type)") { client in
            try await client.uploadImage(id: itemID, type: type, data: data, mimeType: mime)
            self.toasts.success("Uploaded \(type.lowercased()) image")
        }
    }

    // MARK: Metadata

    func saveMetadata(itemID: String, changes: [String: JSONValue]) async -> Bool {
        await perform("save-\(itemID)") { client in
            try await client.updateItem(id: itemID, changes: changes)
            self.toasts.success("Metadata saved")
        }
    }

    func refreshItem(id: String, metadata: JellyfinRefreshMode, images: JellyfinRefreshMode,
                     replaceMetadata: Bool, replaceImages: Bool, recursive: Bool) async -> Bool {
        await perform("refresh-\(id)") { client in
            try await client.refreshItem(id: id, metadata: metadata, images: images,
                                         replaceMetadata: replaceMetadata,
                                         replaceImages: replaceImages, recursive: recursive)
            self.toasts.success("Refresh queued")
        }
    }

    func identify(item: JellyfinItem, name: String, year: Int?, providerIDs: [String: String],
                  indexNumber: Int?, parentIndexNumber: Int?) async -> [JellyfinRemoteSearchResult] {
        let info = JellyfinClient.RemoteSearchQuery.SearchInfo(
            Name: name.isEmpty ? item.Name : name,
            Year: year,
            IndexNumber: indexNumber,
            ParentIndexNumber: parentIndexNumber,
            ProviderIds: providerIDs.isEmpty ? nil : providerIDs,
            PremiereDate: nil,
            MetadataLanguage: "en",
            MetadataCountryCode: "GB")
        let query = JellyfinClient.RemoteSearchQuery(ItemId: item.Id, SearchInfo: info)
        do {
            return try await withAuth { try await $0.remoteSearch(kind: item.kind, query: query) }
        } catch {
            report(error)
            return []
        }
    }

    func applyIdentification(itemID: String, result: JellyfinRemoteSearchResult, replaceImages: Bool) async -> Bool {
        await perform("apply-\(itemID)") { client in
            try await client.applyRemoteSearch(id: itemID, result: result, replaceAllImages: replaceImages)
            self.toasts.success("Match applied — Jellyfin is refreshing the item")
        }
    }

    func deleteItem(id: String) async -> Bool {
        await perform("delete-\(id)") { client in
            try await client.deleteItem(id: id)
            self.items.removeAll { $0.Id == id }
            self.toasts.success("Item deleted from Jellyfin")
        }
    }

    // MARK: Library maintenance

    func scanAll() async {
        _ = await perform("scan") { client in
            try await client.scanAllLibraries()
            self.toasts.success("Library scan started")
        }
    }

    func scanLibrary(_ folder: JellyfinVirtualFolder) async {
        guard let id = folder.ItemId else { return }
        _ = await perform("scan-\(id)") { client in
            try await client.refreshItem(id: id, metadata: .standard, images: .standard,
                                         replaceMetadata: false, replaceImages: false, recursive: true)
            self.toasts.success("Scanning \(folder.Name ?? "library")")
        }
    }

    func runTask(_ task: JellyfinScheduledTask) async {
        guard let id = task.Id else { return }
        _ = await perform("task-\(id)") { client in
            try await client.runTask(id: id)
            self.toasts.success("Started \(task.Name ?? "task")")
        }
    }

    // MARK: Plumbing

    @discardableResult
    private func perform(_ key: String, _ work: @escaping (JellyfinClient) async throws -> Void) async -> Bool {
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await withAuth { try await work($0) }
            return true
        } catch {
            report(error)
            return false
        }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func report(_ error: Error) {
        lastError = errorText(error)
        toasts.error("Jellyfin: \(errorText(error))")
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum JellyfinBrowseType: String, CaseIterable, Identifiable {
    case auto, movies, series, episodes, albums, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Default"
        case .movies: return "Movies"
        case .series: return "Shows"
        case .episodes: return "Episodes"
        case .albums: return "Albums"
        case .all: return "Everything"
        }
    }
    var itemTypes: [String] {
        switch self {
        case .auto, .all: return []
        case .movies: return ["Movie"]
        case .series: return ["Series"]
        case .episodes: return ["Episode"]
        case .albums: return ["MusicAlbum"]
        }
    }
}

enum JellyfinSortOption: String, CaseIterable, Identifiable {
    case sortName = "SortName"
    case dateCreated = "DateCreated"
    case premiereDate = "PremiereDate"
    case communityRating = "CommunityRating"
    case runtime = "Runtime"
    case random = "Random"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sortName: return "Name"
        case .dateCreated: return "Date added"
        case .premiereDate: return "Release date"
        case .communityRating: return "Rating"
        case .runtime: return "Runtime"
        case .random: return "Random"
        }
    }
}
