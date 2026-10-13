import SwiftUI

@MainActor
final class DelugeStore: ObservableObject {
    @Published private(set) var torrents: [DelugeTorrent] = []
    @Published private(set) var stats: DelugeStats?
    @Published private(set) var stateCounts: [DelugeFilterCount] = []
    @Published private(set) var labelCounts: [DelugeFilterCount] = []
    @Published private(set) var trackerCounts: [DelugeFilterCount] = []
    @Published private(set) var labels: [String] = []
    @Published private(set) var version: String?
    @Published private(set) var config: [String: JSONValue] = [:]
    @Published private(set) var hasLabelPlugin = false

    @Published var state: LoadState = .idle
    @Published var lastError: String?
    @Published var busy: Set<String> = []

    // List controls
    @Published var searchText = ""
    @Published var stateFilter = "All"
    @Published var labelFilter: String?
    @Published var sortKey: DelugeSortKey = .queue
    @Published var sortAscending = true

    private(set) var client: DelugeClient?
    private let toasts: ToastCenter
    private var pollTask: Task<Void, Never>?

    init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    var isConfigured: Bool { client != nil }

    func configure(_ endpoint: ServiceEndpoint) {
        client = try? DelugeClient(endpoint: endpoint)
    }

    // MARK: Derived

    var downloadRate: Int { stats?.downloadRate ?? 0 }
    var uploadRate: Int { stats?.uploadRate ?? 0 }
    var freeSpace: Int64 { stats?.free_space ?? 0 }
    var activeCount: Int { torrents.filter(\.isActive).count }
    var downloadingCount: Int { torrents.filter(\.isDownloading).count }
    var seedingCount: Int { torrents.filter(\.isSeeding).count }
    var pausedCount: Int { torrents.filter(\.isPaused).count }
    var errorCount: Int { torrents.filter(\.isError).count }
    var remainingBytes: Int64 { torrents.filter { !($0.is_finished ?? false) }.reduce(0) { $0 + $1.remaining } }

    /// True when everything is paused — Deluge has no single "session paused" flag to read back.
    var isAllPaused: Bool { !torrents.isEmpty && pausedCount == torrents.count }

    var eta: String {
        guard downloadRate > 1024, remainingBytes > 0 else { return "—" }
        return Fmt.duration(Int(remainingBytes / Int64(downloadRate)))
    }

    var filteredTorrents: [DelugeTorrent] {
        var result = torrents
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !term.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(term)
                    || ($0.label ?? "").lowercased().contains(term)
                    || ($0.tracker_host ?? "").lowercased().contains(term)
            }
        }
        if stateFilter != "All" {
            if stateFilter == "Active" {
                result = result.filter(\.isActive)
            } else {
                result = result.filter { ($0.state ?? "") == stateFilter }
            }
        }
        if let labelFilter {
            result = result.filter { ($0.label ?? "") == labelFilter }
        }
        result.sort { a, b in
            let ascending = sortAscending
            func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool { ascending ? lhs < rhs : lhs > rhs }
            switch sortKey {
            case .queue:
                // Deluge parks finished torrents at queue position -1; keep them last.
                let lhs = (a.queue ?? -1) < 0 ? Int.max : (a.queue ?? 0)
                let rhs = (b.queue ?? -1) < 0 ? Int.max : (b.queue ?? 0)
                return compare(lhs, rhs)
            case .name: return compare(a.title.lowercased(), b.title.lowercased())
            case .progress: return compare(a.fraction, b.fraction)
            case .size: return compare(a.total_size ?? 0, b.total_size ?? 0)
            case .ratio: return compare(a.ratio ?? 0, b.ratio ?? 0)
            case .added: return compare(a.time_added ?? 0, b.time_added ?? 0)
            case .downRate: return compare(a.download_payload_rate ?? 0, b.download_payload_rate ?? 0)
            case .upRate: return compare(a.upload_payload_rate ?? 0, b.upload_payload_rate ?? 0)
            }
        }
        return result
    }

    func torrent(hash: String) -> DelugeTorrent? {
        torrents.first { $0.hash.caseInsensitiveCompare(hash) == .orderedSame }
    }

    // MARK: Loading

    func load(force: Bool = false) async {
        guard let client else { return }
        if state == .idle { state = .loading }
        do {
            try await client.authenticated {
                let ui = try await client.updateUI()
                apply(ui)
            }
            if version == nil { version = try? await client.version() }
            if config.isEmpty {
                config = (try? await client.configValues([
                    "download_location", "move_completed_path", "max_download_speed",
                    "max_upload_speed", "max_active_downloading", "max_connections_global",
                ])) ?? [:]
            }
            if labels.isEmpty {
                let plugins = (try? await client.enabledPlugins()) ?? []
                hasLabelPlugin = plugins.contains("Label")
                if hasLabelPlugin { labels = (try? await client.labels()) ?? [] }
            }
            state = .loaded
            lastError = nil
        } catch {
            state = .failed(errorText(error))
            lastError = errorText(error)
        }
    }

    /// Light refresh for the polling loop.
    func poll() async {
        guard let client else { return }
        do {
            try await client.authenticated {
                let ui = try await client.updateUI()
                apply(ui)
            }
            if state != .loaded { state = .loaded }
        } catch {
            lastError = errorText(error)
        }
    }

    private func apply(_ ui: DelugeUpdateUI) {
        torrents = (ui.torrents ?? [:]).map { hash, torrent in
            var copy = torrent
            copy.hash = hash
            return copy
        }
        stats = ui.stats
        stateCounts = DelugeFilterCount.parse(ui.filters?["state"])
        labelCounts = DelugeFilterCount.parse(ui.filters?["label"]).filter { $0.name != "All" }
        trackerCounts = DelugeFilterCount.parse(ui.filters?["tracker_host"])
            .filter { $0.name != "All" && !$0.name.isEmpty }
    }

    func startPolling(interval: Double) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: UInt64(max(2, interval) * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Actions

    func setPaused(_ hashes: [String], paused: Bool) async {
        await perform("pause-\(hashes.first ?? "")") { client in
            if paused { try await client.pause(hashes) } else { try await client.resume(hashes) }
            await self.poll()
        }
    }

    func remove(_ hashes: [String], deleteData: Bool) async {
        await perform("remove-\(hashes.first ?? "")") { client in
            try await client.remove(hashes, deleteData: deleteData)
            self.torrents.removeAll { hashes.contains($0.hash) }
            self.toasts.success(deleteData
                ? "Removed \(hashes.count) torrent\(hashes.count == 1 ? "" : "s") and deleted data"
                : "Removed \(hashes.count) torrent\(hashes.count == 1 ? "" : "s")")
            await self.poll()
        }
    }

    func forceRecheck(_ hashes: [String]) async {
        await perform("recheck-\(hashes.first ?? "")") { client in
            try await client.forceRecheck(hashes)
            self.toasts.info("Rechecking data")
            await self.poll()
        }
    }

    func queueMove(_ hashes: [String], _ move: DelugeClient.QueueMove) async {
        await perform("queue-\(hashes.first ?? "")") { client in
            try await client.queueMove(hashes, move)
            await self.poll()
        }
    }

    func setLabel(_ hash: String, label: String) async {
        await perform("label-\(hash)") { client in
            try await client.setLabel(hash, label: label)
            self.toasts.success(label.isEmpty ? "Label cleared" : "Labelled \(label)")
            await self.poll()
        }
    }

    func createLabel(_ label: String) async {
        await perform("newlabel") { client in
            try await client.addLabel(label)
            self.labels = (try? await client.labels()) ?? self.labels
            self.toasts.success("Created label \(label)")
        }
    }

    func setTorrentSpeedLimit(_ hashes: [String], downloadKiB: Double) async {
        await perform("limit-\(hashes.first ?? "")") { client in
            try await client.setTorrentOptions(hashes, ["max_download_speed": .number(downloadKiB)])
            self.toasts.success(downloadKiB < 0 ? "Speed limit removed" : "Limited to \(Int(downloadKiB)) KiB/s")
            await self.poll()
        }
    }

    func setSessionPaused(_ paused: Bool) async {
        await perform("session") { client in
            if paused { try await client.pauseSession() } else { try await client.resumeSession() }
            self.toasts.success(paused ? "All torrents paused" : "All torrents resumed")
            await self.poll()
        }
    }

    func setSpeedLimits(download: Double?, upload: Double?) async {
        await perform("rate") { client in
            try await client.setSpeedLimits(download: download, upload: upload)
            if let download {
                self.toasts.success(download < 0 ? "Download limit removed"
                                                 : "Download limited to \(Int(download)) KiB/s")
            }
            if let upload, download == nil {
                self.toasts.success(upload < 0 ? "Upload limit removed"
                                               : "Upload limited to \(Int(upload)) KiB/s")
            }
            await self.poll()
        }
    }

    func add(_ uri: String, label: String, paused: Bool, downloadLocation: String?) async -> Bool {
        guard let client else { return false }
        busy.insert("add")
        defer { busy.remove("add") }
        var options: [String: JSONValue] = ["add_paused": .bool(paused)]
        if let downloadLocation, !downloadLocation.isEmpty {
            options["download_location"] = .string(downloadLocation)
        }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let hash: String? = try await client.authenticated {
                trimmed.hasPrefix("magnet:")
                    ? try await client.addMagnet(trimmed, options: options)
                    : try await client.addURL(trimmed, options: options)
            }
            if let hash, !label.isEmpty, hasLabelPlugin {
                try? await client.setLabel(hash, label: label)
            }
            toasts.success(hash == nil ? "Deluge accepted the torrent" : "Torrent added")
            await load(force: true)
            return true
        } catch {
            toasts.error("Deluge: \(errorText(error))")
            return false
        }
    }

    // MARK: Plumbing

    private func perform(_ key: String, _ work: @escaping (DelugeClient) async throws -> Void) async {
        guard let client else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await client.authenticated { try await work(client) }
        } catch {
            lastError = errorText(error)
            toasts.error("Deluge: \(errorText(error))")
        }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func errorText(_ error: Error) -> String {
        if error is DelugeClient.NotAuthenticated { return "Not authenticated — check the password in Settings." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
