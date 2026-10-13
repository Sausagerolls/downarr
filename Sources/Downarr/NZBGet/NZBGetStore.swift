import SwiftUI

@MainActor
final class NZBGetStore: ObservableObject {
    @Published private(set) var status: NZBGetStatus?
    @Published private(set) var groups: [NZBGetGroup] = []
    @Published private(set) var history: [NZBGetHistoryItem] = []
    @Published private(set) var categories: [String] = []
    @Published private(set) var version: String?

    @Published var state: LoadState = .idle
    @Published var lastError: String?
    @Published var busy: Set<String> = []
    @Published var historySearch = ""

    private(set) var client: NZBGetClient?
    private let toasts: ToastCenter
    private var pollTask: Task<Void, Never>?

    init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    var isConfigured: Bool { client != nil }

    func configure(_ endpoint: ServiceEndpoint) {
        client = try? NZBGetClient(endpoint: endpoint)
    }

    // MARK: Derived

    var activeGroups: [NZBGetGroup] { groups.filter { ($0.ActiveDownloads ?? 0) > 0 } }
    var remainingBytes: Int64 { Int64(status?.RemainingSizeMB ?? 0) * 1_048_576 }
    var freeDiskBytes: Int64 { Int64(status?.FreeDiskSpaceMB ?? 0) * 1_048_576 }
    var downloadRate: Int { status?.DownloadRate ?? 0 }
    var isPaused: Bool { status?.DownloadPaused ?? false }

    var eta: String {
        let rate = downloadRate
        guard rate > 1024, remainingBytes > 0 else { return "—" }
        return Fmt.duration(Int(remainingBytes / Int64(rate)))
    }

    var filteredHistory: [NZBGetHistoryItem] {
        let term = historySearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return history }
        return history.filter {
            $0.name.lowercased().contains(term) || ($0.Category ?? "").lowercased().contains(term)
        }
    }

    // MARK: Loading

    func load(force: Bool = false) async {
        guard let client else { return }
        if state == .idle { state = .loading }
        do {
            async let statusTask = client.status()
            async let groupsTask = client.groups()
            async let historyTask = client.history()
            status = try await statusTask
            groups = try await groupsTask
            history = try await historyTask
            state = .loaded
            lastError = nil
            if categories.isEmpty {
                categories = (try? await client.categories()) ?? []
            }
            if version == nil { version = try? await client.version() }
        } catch {
            state = .failed(errorText(error))
            lastError = errorText(error)
        }
    }

    /// Light refresh used by the polling loop — status + queue only.
    func poll() async {
        guard let client else { return }
        do {
            async let statusTask = client.status()
            async let groupsTask = client.groups()
            status = try await statusTask
            groups = try await groupsTask
            if state != .loaded { state = .loaded }
        } catch {
            lastError = errorText(error)
        }
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

    func togglePause() async {
        await setPaused(.downloads, !isPaused)
    }

    /// The three independently pausable NZBGet subsystems.
    enum PauseTarget: CaseIterable {
        case downloads, postProcessing, scanning

        var label: String {
            switch self {
            case .downloads: return "Downloads"
            case .postProcessing: return "Post-processing"
            case .scanning: return "Watch folder scanning"
            }
        }
    }

    func isPaused(_ target: PauseTarget) -> Bool {
        switch target {
        case .downloads: return status?.DownloadPaused ?? false
        case .postProcessing: return status?.PostPaused ?? false
        case .scanning: return status?.ScanPaused ?? false
        }
    }

    var allPaused: Bool { PauseTarget.allCases.allSatisfy { isPaused($0) } }

    func setPaused(_ target: PauseTarget, _ paused: Bool) async {
        await perform("pause-\(target)") { client in
            try await Self.apply(target, paused: paused, client: client)
            self.toasts.success("\(target.label) \(paused ? "paused" : "resumed")")
            await self.poll()
        }
    }

    func setAllPaused(_ paused: Bool) async {
        await perform("pause-all") { client in
            for target in PauseTarget.allCases {
                try await Self.apply(target, paused: paused, client: client)
            }
            self.toasts.success(paused ? "NZBGet fully paused" : "NZBGet fully resumed")
            await self.poll()
        }
    }

    private static func apply(_ target: PauseTarget, paused: Bool, client: NZBGetClient) async throws {
        switch (target, paused) {
        case (.downloads, true): _ = try await client.pauseDownload()
        case (.downloads, false): _ = try await client.resumeDownload()
        case (.postProcessing, true): _ = try await client.pausePost()
        case (.postProcessing, false): _ = try await client.resumePost()
        case (.scanning, true): _ = try await client.pauseScan()
        case (.scanning, false): _ = try await client.resumeScan()
        }
    }

    func setSpeedLimit(kilobytesPerSecond: Int) async {
        await perform("rate") { client in
            _ = try await client.setRate(kilobytesPerSecond: kilobytesPerSecond)
            self.toasts.success(kilobytesPerSecond == 0
                ? "Speed limit removed"
                : "Speed limited to \(kilobytesPerSecond) KB/s")
            await self.poll()
        }
    }

    func pauseGroups(_ ids: [Int], paused: Bool) async {
        await perform("group-\(ids.first ?? 0)") { client in
            if paused { try await client.pause(ids: ids) } else { try await client.resume(ids: ids) }
            await self.poll()
        }
    }

    func deleteGroups(_ ids: [Int], deleteFiles: Bool) async {
        await perform("delete-\(ids.first ?? 0)") { client in
            try await client.delete(ids: ids, deleteFiles: deleteFiles)
            self.groups.removeAll { ids.contains($0.NZBID) }
            self.toasts.success(ids.count == 1 ? "Removed from queue" : "Removed \(ids.count) items")
            await self.load(force: true)
        }
    }

    func move(_ ids: [Int], to position: MovePosition) async {
        await perform("move-\(ids.first ?? 0)") { client in
            switch position {
            case .top: try await client.moveTop(ids: ids)
            case .bottom: try await client.moveBottom(ids: ids)
            case .up: try await client.move(ids: ids, offset: -1)
            case .down: try await client.move(ids: ids, offset: 1)
            }
            await self.poll()
        }
    }

    enum MovePosition { case top, bottom, up, down }

    func setPriority(_ ids: [Int], priority: NZBGetPriority) async {
        await perform("priority-\(ids.first ?? 0)") { client in
            try await client.setPriority(ids: ids, priority: priority.rawValue)
            self.toasts.success("Priority set to \(priority.label)")
            await self.poll()
        }
    }

    func setCategory(_ ids: [Int], category: String) async {
        await perform("category-\(ids.first ?? 0)") { client in
            try await client.setCategory(ids: ids, category: category)
            await self.poll()
        }
    }

    func historyAction(_ ids: [Int], _ action: HistoryAction) async {
        await perform("history-\(ids.first ?? 0)") { client in
            switch action {
            case .delete: try await client.historyDelete(ids: ids)
            case .deleteFinal: try await client.historyFinalDelete(ids: ids)
            case .redownload: try await client.historyRedownload(ids: ids)
            case .returnToQueue: try await client.historyReturn(ids: ids)
            case .markGood: try await client.historyMarkGood(ids: ids)
            case .markBad: try await client.historyMarkBad(ids: ids)
            }
            self.toasts.success(action.confirmation)
            await self.load(force: true)
        }
    }

    enum HistoryAction {
        case delete, deleteFinal, redownload, returnToQueue, markGood, markBad
        var confirmation: String {
            switch self {
            case .delete: return "Removed from history"
            case .deleteFinal: return "Deleted with files"
            case .redownload: return "Re-downloading"
            case .returnToQueue: return "Returned to queue"
            case .markGood: return "Marked good"
            case .markBad: return "Marked bad"
            }
        }
    }

    func addURL(_ url: String, category: String, priority: NZBGetPriority, paused: Bool, addToTop: Bool) async -> Bool {
        guard let client else { return false }
        busy.insert("append")
        defer { busy.remove("append") }
        do {
            let id = try await client.appendURL(url, category: category,
                                                priority: priority.rawValue,
                                                paused: paused, addToTop: addToTop)
            toasts.success(id > 0 ? "NZB queued" : "NZBGet accepted the URL")
            await load(force: true)
            return true
        } catch {
            toasts.error("NZBGet: \(errorText(error))")
            return false
        }
    }

    func scan() async {
        await perform("scan") { client in
            _ = try await client.scan()
            self.toasts.success("Scanning watch folder")
        }
    }

    func reload() async {
        await perform("reload") { client in
            _ = try await client.reload()
            self.toasts.info("NZBGet reloading")
        }
    }

    // MARK: Plumbing

    private func perform(_ key: String, _ work: @escaping (NZBGetClient) async throws -> Void) async {
        guard let client else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do { try await work(client) } catch {
            lastError = errorText(error)
            toasts.error("NZBGet: \(errorText(error))")
        }
    }

    func isBusy(_ key: String) -> Bool { busy.contains(key) }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
