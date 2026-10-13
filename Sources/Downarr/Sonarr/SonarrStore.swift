import SwiftUI

@MainActor
final class SonarrStore: ObservableObject {
    @Published private(set) var series: [SonarrSeries] = []
    @Published private(set) var status: ArrSystemStatus?
    @Published private(set) var health: [ArrHealth] = []
    @Published private(set) var queue: [SonarrQueueRecord] = []
    @Published private(set) var missing: [SonarrEpisode] = []
    @Published private(set) var history: [SonarrHistoryRecord] = []
    @Published private(set) var profiles: [ArrQualityProfile] = []
    @Published private(set) var rootFolders: [ArrRootFolder] = []
    @Published private(set) var diskSpace: [ArrDiskSpace] = []
    @Published private(set) var episodesBySeries: [Int: [SonarrEpisode]] = [:]

    @Published var libraryState: LoadState = .idle
    @Published var queueState: LoadState = .idle
    @Published var lastError: String?
    @Published var busy: Set<String> = []

    // Library controls
    @Published var searchText = ""
    @Published var filter: ArrMonitorFilter = .all
    @Published var sortKey: ArrSortKey = .title
    @Published var sortAscending = true

    private(set) var client: SonarrClient?
    private let toasts: ToastCenter

    init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    var isConfigured: Bool { client != nil }

    func configure(_ endpoint: ServiceEndpoint) {
        client = try? SonarrClient(endpoint: endpoint)
    }

    // MARK: Derived

    var filteredSeries: [SonarrSeries] {
        var result = series
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !term.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(term)
                    || ($0.network ?? "").lowercased().contains(term)
                    || ($0.genres ?? []).contains { $0.lowercased().contains(term) }
            }
        }
        switch filter {
        case .all: break
        case .monitored: result = result.filter(\.monitored)
        case .unmonitored: result = result.filter { !$0.monitored }
        case .missing: result = result.filter { $0.missingCount > 0 }
        case .complete: result = result.filter { $0.missingCount == 0 && $0.sizeOnDisk > 0 }
        }
        result.sort { a, b in
            let ascending = sortAscending
            func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
                ascending ? lhs < rhs : lhs > rhs
            }
            switch sortKey {
            case .title: return compare(a.sortTitle ?? a.title.lowercased(), b.sortTitle ?? b.title.lowercased())
            case .added: return compare(a.added ?? .distantPast, b.added ?? .distantPast)
            case .year: return compare(a.year ?? 0, b.year ?? 0)
            case .size: return compare(a.sizeOnDisk, b.sizeOnDisk)
            case .progress: return compare(a.completion, b.completion)
            case .rating: return compare(a.ratings?.value ?? 0, b.ratings?.value ?? 0)
            }
        }
        return result
    }

    var totalSize: Int64 { series.reduce(0) { $0 + $1.sizeOnDisk } }
    var episodeFileCount: Int { series.reduce(0) { $0 + ($1.statistics?.episodeFileCount ?? 0) } }
    var missingEpisodeCount: Int { series.reduce(0) { $0 + $1.missingCount } }
    var monitoredCount: Int { series.filter(\.monitored).count }

    func series(id: Int) -> SonarrSeries? { series.first { $0.id == id } }

    func posterURL(_ item: SonarrSeries) -> URL? { client?.images.url(item.images, type: "poster") }
    func fanartURL(_ item: SonarrSeries) -> URL? {
        client?.images.url(item.images, type: "fanart") ?? client?.images.url(item.images, type: "banner")
    }
    func lookupPosterURL(_ item: SonarrSeries) -> URL? { client?.images.remoteURL(item.images, type: "poster") }

    func profileName(_ id: Int?) -> String {
        guard let id else { return "—" }
        return profiles.first { $0.id == id }?.name ?? "Profile \(id)"
    }

    // MARK: Loading

    func loadAll(force: Bool = false) async {
        guard let client else { return }
        if !force, case .loaded = libraryState { return }
        libraryState = .loading
        async let seriesTask = client.series()
        async let statusTask = client.status()
        async let healthTask = client.health()
        async let profilesTask = client.qualityProfiles()
        async let rootsTask = client.rootFolders()
        async let diskTask = client.diskSpace()
        do {
            series = try await seriesTask
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

    func reloadSeries(id: Int) async {
        guard let client else { return }
        do {
            let updated = try await client.series(id: id)
            replace(updated)
        } catch {
            report(error)
        }
    }

    private func replace(_ updated: SonarrSeries) {
        guard let id = updated.id else { return }
        if let index = series.firstIndex(where: { $0.id == id }) {
            series[index] = updated
        } else {
            series.append(updated)
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

    func episodes(seriesID: Int) -> [SonarrEpisode] { episodesBySeries[seriesID] ?? [] }

    func loadEpisodes(seriesID: Int, force: Bool = false) async {
        guard let client else { return }
        if !force, episodesBySeries[seriesID] != nil { return }
        do {
            episodesBySeries[seriesID] = try await client.episodes(seriesID: seriesID)
        } catch {
            report(error)
        }
    }

    func calendar(start: Date, end: Date) async -> [SonarrEpisode] {
        guard let client else { return [] }
        do { return try await client.calendar(start: start, end: end) } catch { report(error); return [] }
    }

    func lookup(_ term: String) async -> [SonarrSeries] {
        guard let client, term.count > 1 else { return [] }
        do { return try await client.lookup(term) } catch { report(error); return [] }
    }

    func releases(episodeID: Int) async -> [ArrRelease] {
        guard let client else { return [] }
        do { return try await client.releases(episodeID: episodeID) } catch { report(error); return [] }
    }

    func releases(seriesID: Int, seasonNumber: Int) async -> [ArrRelease] {
        guard let client else { return [] }
        do { return try await client.releases(seriesID: seriesID, seasonNumber: seasonNumber) }
        catch { report(error); return [] }
    }

    // MARK: Mutations

    func setMonitored(seriesID: Int, monitored: Bool) async {
        await perform("monitor-\(seriesID)") { client in
            let updated = try await client.patchSeries(id: seriesID, changes: ["monitored": .bool(monitored)])
            self.replace(updated)
            self.toasts.success("\(updated.title) \(monitored ? "monitored" : "unmonitored")")
        }
    }

    func setSeasonMonitored(seriesID: Int, seasonNumber: Int, monitored: Bool) async {
        await perform("season-\(seriesID)-\(seasonNumber)") { client in
            let updated = try await client.setSeasonMonitored(seriesID: seriesID,
                                                              seasonNumber: seasonNumber,
                                                              monitored: monitored)
            self.replace(updated)
        }
    }

    func setEpisodeMonitored(seriesID: Int, episodeIDs: [Int], monitored: Bool) async {
        await perform("episodes-\(seriesID)") { client in
            try await client.setEpisodesMonitored(ids: episodeIDs, monitored: monitored)
            await self.loadEpisodes(seriesID: seriesID, force: true)
        }
    }

    func edit(seriesID: Int, changes: [String: JSONValue]) async {
        await perform("edit-\(seriesID)") { client in
            let updated = try await client.patchSeries(id: seriesID, changes: changes)
            self.replace(updated)
            self.toasts.success("Saved \(updated.title)")
        }
    }

    func deleteSeries(id: Int, deleteFiles: Bool, addExclusion: Bool) async {
        await perform("delete-\(id)") { client in
            let title = self.series(id: id)?.title ?? "Series"
            try await client.deleteSeries(id: id, deleteFiles: deleteFiles, addExclusion: addExclusion)
            self.series.removeAll { $0.id == id }
            self.toasts.success("Removed \(title)")
        }
    }

    func addSeries(_ request: SonarrAddSeriesRequest) async -> Bool {
        guard let client else { return false }
        busy.insert("add")
        defer { busy.remove("add") }
        do {
            let added = try await client.addSeries(request)
            replace(added)
            toasts.success("Added \(added.title)")
            return true
        } catch {
            report(error)
            return false
        }
    }

    func search(seriesID: Int) async {
        await perform("search-\(seriesID)") { client in
            try await client.searchSeries(seriesID)
            self.toasts.success("Search started")
        }
    }

    func searchSeason(seriesID: Int, seasonNumber: Int) async {
        await perform("search-\(seriesID)-\(seasonNumber)") { client in
            try await client.searchSeason(seriesID: seriesID, seasonNumber: seasonNumber)
            self.toasts.success("Searching season \(seasonNumber)")
        }
    }

    func searchEpisodes(_ ids: [Int]) async {
        await perform("search-eps") { client in
            try await client.searchEpisodes(ids)
            self.toasts.success(ids.count == 1 ? "Episode search started" : "Searching \(ids.count) episodes")
        }
    }

    func grab(_ release: ArrRelease) async {
        await perform("grab-\(release.id)") { client in
            try await client.grab(release)
            self.toasts.success("Sent to download client")
        }
    }

    func refresh(seriesID: Int) async {
        await perform("refresh-\(seriesID)") { client in
            try await client.refresh(seriesID: seriesID)
            self.toasts.success("Refreshing metadata")
        }
    }

    func rescan(seriesID: Int) async {
        await perform("rescan-\(seriesID)") { client in
            try await client.rescan(seriesID: seriesID)
            self.toasts.success("Rescanning files")
        }
    }

    func rename(seriesID: Int) async {
        await perform("rename-\(seriesID)") { client in
            try await client.renameFiles(seriesID: seriesID)
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

    func deleteEpisodeFile(id: Int, seriesID: Int) async {
        await perform("file-\(id)") { client in
            try await client.deleteEpisodeFile(id: id)
            await self.loadEpisodes(seriesID: seriesID, force: true)
            self.toasts.success("File deleted")
        }
    }

    // MARK: Plumbing

    private func perform(_ key: String, _ work: @escaping (SonarrClient) async throws -> Void) async {
        guard let client else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do { try await work(client) } catch { report(error) }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func report(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        toasts.error("Sonarr: \(message)")
    }
}
