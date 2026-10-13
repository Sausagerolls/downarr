import SwiftUI

@MainActor
final class RadarrStore: ObservableObject {
    @Published private(set) var movies: [RadarrMovie] = []
    @Published private(set) var status: ArrSystemStatus?
    @Published private(set) var health: [ArrHealth] = []
    @Published private(set) var queue: [RadarrQueueRecord] = []
    @Published private(set) var missing: [RadarrMovie] = []
    @Published private(set) var history: [RadarrHistoryRecord] = []
    @Published private(set) var profiles: [ArrQualityProfile] = []
    @Published private(set) var rootFolders: [ArrRootFolder] = []
    @Published private(set) var diskSpace: [ArrDiskSpace] = []

    @Published var libraryState: LoadState = .idle
    @Published var queueState: LoadState = .idle
    @Published var lastError: String?
    @Published var busy: Set<String> = []

    @Published var searchText = ""
    @Published var filter: ArrMonitorFilter = .all
    @Published var sortKey: ArrSortKey = .title
    @Published var sortAscending = true

    private(set) var client: RadarrClient?
    private let toasts: ToastCenter

    init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    var isConfigured: Bool { client != nil }

    func configure(_ endpoint: ServiceEndpoint) {
        client = try? RadarrClient(endpoint: endpoint)
    }

    // MARK: Derived

    var filteredMovies: [RadarrMovie] {
        var result = movies
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !term.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(term)
                    || ($0.originalTitle ?? "").lowercased().contains(term)
                    || ($0.studio ?? "").lowercased().contains(term)
                    || ($0.genres ?? []).contains { $0.lowercased().contains(term) }
            }
        }
        switch filter {
        case .all: break
        case .monitored: result = result.filter(\.monitored)
        case .unmonitored: result = result.filter { !$0.monitored }
        case .missing: result = result.filter { !($0.hasFile ?? false) }
        case .complete: result = result.filter { $0.hasFile ?? false }
        }
        result.sort { a, b in
            let ascending = sortAscending
            func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool { ascending ? lhs < rhs : lhs > rhs }
            switch sortKey {
            case .title: return compare(a.sortTitle ?? a.title.lowercased(), b.sortTitle ?? b.title.lowercased())
            case .added: return compare(a.added ?? .distantPast, b.added ?? .distantPast)
            case .year: return compare(a.year ?? 0, b.year ?? 0)
            case .size: return compare(a.sizeOnDisk ?? 0, b.sizeOnDisk ?? 0)
            case .progress: return compare((a.hasFile ?? false) ? 1 : 0, (b.hasFile ?? false) ? 1 : 0)
            case .rating: return compare(a.ratings?.best ?? 0, b.ratings?.best ?? 0)
            }
        }
        return result
    }

    var totalSize: Int64 { movies.reduce(0) { $0 + ($1.sizeOnDisk ?? 0) } }
    var downloadedCount: Int { movies.filter { $0.hasFile ?? false }.count }
    var missingCount: Int { movies.filter(\.isMissing).count }
    var monitoredCount: Int { movies.filter(\.monitored).count }

    func movie(id: Int) -> RadarrMovie? { movies.first { $0.id == id } }

    func posterURL(_ item: RadarrMovie) -> URL? { client?.images.url(item.images, type: "poster") }
    func fanartURL(_ item: RadarrMovie) -> URL? { client?.images.url(item.images, type: "fanart") }
    func lookupPosterURL(_ item: RadarrMovie) -> URL? { client?.images.remoteURL(item.images, type: "poster") }

    func profileName(_ id: Int?) -> String {
        guard let id else { return "—" }
        return profiles.first { $0.id == id }?.name ?? "Profile \(id)"
    }

    // MARK: Loading

    func loadAll(force: Bool = false) async {
        guard let client else { return }
        if !force, case .loaded = libraryState { return }
        libraryState = .loading
        async let moviesTask = client.movies()
        async let statusTask = client.status()
        async let healthTask = client.health()
        async let profilesTask = client.qualityProfiles()
        async let rootsTask = client.rootFolders()
        async let diskTask = client.diskSpace()
        do {
            movies = try await moviesTask
            status = try? await statusTask
            health = (try? await healthTask) ?? []
            profiles = (try? await profilesTask) ?? []
            rootFolders = (try? await rootsTask) ?? []
            diskSpace = (try? await diskTask) ?? []
            libraryState = .loaded
            lastError = nil
        } catch {
            libraryState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func reloadMovie(id: Int) async {
        guard let client else { return }
        do { replace(try await client.movie(id: id)) } catch { report(error) }
    }

    private func replace(_ updated: RadarrMovie) {
        guard let id = updated.id else { return }
        if let index = movies.firstIndex(where: { $0.id == id }) {
            movies[index] = updated
        } else {
            movies.append(updated)
        }
    }

    func loadQueue() async {
        guard let client else { return }
        queueState = .loading
        do {
            queue = try await client.queue().records ?? []
            queueState = .loaded
        } catch {
            queueState = .failed(error.localizedDescription)
        }
    }

    func loadMissing() async {
        guard let client else { return }
        do { missing = try await client.missing().records ?? [] } catch { report(error) }
    }

    func loadHistory() async {
        guard let client else { return }
        do { history = try await client.history().records ?? [] } catch { report(error) }
    }

    func calendar(start: Date, end: Date) async -> [RadarrMovie] {
        guard let client else { return [] }
        do { return try await client.calendar(start: start, end: end) } catch { report(error); return [] }
    }

    func lookup(_ term: String) async -> [RadarrMovie] {
        guard let client, term.count > 1 else { return [] }
        do { return try await client.lookup(term) } catch { report(error); return [] }
    }

    func releases(movieID: Int) async -> [ArrRelease] {
        guard let client else { return [] }
        do { return try await client.releases(movieID: movieID) } catch { report(error); return [] }
    }

    // MARK: Mutations

    func setMonitored(movieID: Int, monitored: Bool) async {
        await perform("monitor-\(movieID)") { client in
            let updated = try await client.patchMovie(id: movieID, changes: ["monitored": .bool(monitored)])
            self.replace(updated)
            self.toasts.success("\(updated.title) \(monitored ? "monitored" : "unmonitored")")
        }
    }

    func edit(movieID: Int, changes: [String: JSONValue]) async {
        await perform("edit-\(movieID)") { client in
            let updated = try await client.patchMovie(id: movieID, changes: changes)
            self.replace(updated)
            self.toasts.success("Saved \(updated.title)")
        }
    }

    func deleteMovie(id: Int, deleteFiles: Bool, addExclusion: Bool) async {
        await perform("delete-\(id)") { client in
            let title = self.movie(id: id)?.title ?? "Movie"
            try await client.deleteMovie(id: id, deleteFiles: deleteFiles, addExclusion: addExclusion)
            self.movies.removeAll { $0.id == id }
            self.toasts.success("Removed \(title)")
        }
    }

    func addMovie(_ request: RadarrAddMovieRequest) async -> Bool {
        guard let client else { return false }
        busy.insert("add")
        defer { busy.remove("add") }
        do {
            let added = try await client.addMovie(request)
            replace(added)
            toasts.success("Added \(added.title)")
            return true
        } catch {
            report(error)
            return false
        }
    }

    func search(movieIDs: [Int]) async {
        await perform("search-\(movieIDs.first ?? 0)") { client in
            try await client.searchMovies(movieIDs)
            self.toasts.success(movieIDs.count == 1 ? "Search started" : "Searching \(movieIDs.count) movies")
        }
    }

    func grab(_ release: ArrRelease) async {
        await perform("grab-\(release.id)") { client in
            try await client.grab(release)
            self.toasts.success("Sent to download client")
        }
    }

    func refresh(movieID: Int) async {
        await perform("refresh-\(movieID)") { client in
            try await client.refresh(movieID: movieID)
            self.toasts.success("Refreshing metadata")
        }
    }

    func rescan(movieID: Int) async {
        await perform("rescan-\(movieID)") { client in
            try await client.rescan(movieID: movieID)
            self.toasts.success("Rescanning files")
        }
    }

    func rename(movieID: Int) async {
        await perform("rename-\(movieID)") { client in
            try await client.renameFiles(movieID: movieID)
            self.toasts.success("Rename queued")
        }
    }

    func removeFromQueue(id: Int, removeFromClient: Bool, blocklist: Bool) async {
        await perform("queue-\(id)") { client in
            try await client.removeFromQueue(id: id, removeFromClient: removeFromClient, blocklist: blocklist)
            self.queue.removeAll { $0.id == id }
            self.toasts.success("Removed from queue")
        }
    }

    func deleteMovieFile(id: Int, movieID: Int) async {
        await perform("file-\(id)") { client in
            try await client.deleteMovieFile(id: id)
            await self.reloadMovie(id: movieID)
            self.toasts.success("File deleted")
        }
    }

    // MARK: Plumbing

    private func perform(_ key: String, _ work: @escaping (RadarrClient) async throws -> Void) async {
        guard let client else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do { try await work(client) } catch { report(error) }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func report(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        toasts.error("Radarr: \(message)")
    }
}
