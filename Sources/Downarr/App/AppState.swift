import SwiftUI

/// Owns configuration and the four service stores, and keeps clients in sync with settings.
@MainActor
final class AppState: ObservableObject {
    let config = ConfigStore()
    let toasts = ToastCenter()
    let sonarr: SonarrStore
    let radarr: RadarrStore
    let jellyfin: JellyfinStore
    let nzbget: NZBGetStore
    let deluge: DelugeStore

    @Published var selection: SidebarItem? = .dashboard

    init() {
        sonarr = SonarrStore(toasts: toasts)
        radarr = RadarrStore(toasts: toasts)
        jellyfin = JellyfinStore(toasts: toasts, config: config)
        nzbget = NZBGetStore(toasts: toasts)
        deluge = DelugeStore(toasts: toasts)
        applyConfiguration()
    }

    func applyConfiguration() {
        sonarr.configure(config.config.sonarr)
        radarr.configure(config.config.radarr)
        jellyfin.configure(config.config.jellyfin)
        nzbget.configure(config.config.nzbget)
        deluge.configure(config.config.deluge)
    }

    /// Kicks off the initial fetch for every service.
    ///
    /// macOS can refuse the very first requests while it decides on local-network permission —
    /// and a rebuilt app is re-signed, which makes it re-evaluate. The polling clients recover on
    /// their own; one-shot loads would otherwise leave an empty dashboard until each screen is
    /// visited, so anything that failed is retried with a short backoff.
    func bootstrap() async {
        async let s: Void = sonarr.loadAll()
        async let r: Void = radarr.loadAll()
        async let n: Void = nzbget.load()
        async let d: Void = deluge.load()
        async let j: Void = jellyfin.loadOverview()
        _ = await (s, r, n, d, j)

        for delay in [2.0, 6.0] {
            guard !failedServices.isEmpty else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await retryFailedServices()
        }
    }

    /// Names of the services whose last load ended in an error.
    var failedServices: [String] {
        var names: [String] = []
        if sonarr.libraryState.errorMessage != nil { names.append("Sonarr") }
        if radarr.libraryState.errorMessage != nil { names.append("Radarr") }
        if jellyfin.connectionState.errorMessage != nil { names.append("Jellyfin") }
        if nzbget.state.errorMessage != nil { names.append("NZBGet") }
        if deluge.state.errorMessage != nil { names.append("Deluge") }
        return names
    }

    func retryFailedServices() async {
        await withTaskGroup(of: Void.self) { group in
            if sonarr.libraryState.errorMessage != nil {
                group.addTask { await self.sonarr.loadAll(force: true) }
            }
            if radarr.libraryState.errorMessage != nil {
                group.addTask { await self.radarr.loadAll(force: true) }
            }
            if jellyfin.connectionState.errorMessage != nil {
                group.addTask { await self.jellyfin.loadOverview(force: true) }
            }
            if nzbget.state.errorMessage != nil {
                group.addTask { await self.nzbget.load(force: true) }
            }
            if deluge.state.errorMessage != nil {
                group.addTask { await self.deluge.load(force: true) }
            }
        }
    }

    func refreshEverything() async {
        async let s: Void = sonarr.loadAll(force: true)
        async let r: Void = radarr.loadAll(force: true)
        async let n: Void = nzbget.load(force: true)
        async let d: Void = deluge.load(force: true)
        async let j: Void = jellyfin.loadOverview(force: true)
        _ = await (s, r, n, d, j)
    }
}

enum SidebarItem: Hashable, Identifiable, CaseIterable {
    case dashboard, activity, calendar
    case sonarrLibrary, sonarrWanted, sonarrHistory
    case radarrLibrary, radarrWanted, radarrHistory
    case jellyfinLibraries, jellyfinBrowse
    case downloadQueue, downloadHistory, downloadStatus
    case delugeTorrents, delugeServer
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .activity: return "Activity"
        case .calendar: return "Calendar"
        case .sonarrLibrary: return "Series"
        case .sonarrWanted: return "Wanted"
        case .sonarrHistory: return "History"
        case .radarrLibrary: return "Movies"
        case .radarrWanted: return "Wanted"
        case .radarrHistory: return "History"
        case .jellyfinLibraries: return "Libraries"
        case .jellyfinBrowse: return "Browse"
        case .downloadQueue: return "Queue"
        case .downloadHistory: return "History"
        case .downloadStatus: return "Server"
        case .delugeTorrents: return "Torrents"
        case .delugeServer: return "Server"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .activity: return "waveform.path.ecg"
        case .calendar: return "calendar"
        case .sonarrLibrary: return "tv"
        case .sonarrWanted: return "exclamationmark.magnifyingglass"
        case .sonarrHistory: return "clock.arrow.circlepath"
        case .radarrLibrary: return "film"
        case .radarrWanted: return "exclamationmark.magnifyingglass"
        case .radarrHistory: return "clock.arrow.circlepath"
        case .jellyfinLibraries: return "books.vertical"
        case .jellyfinBrowse: return "square.grid.3x3"
        case .downloadQueue: return "arrow.down.circle"
        case .downloadHistory: return "tray.full"
        case .downloadStatus: return "server.rack"
        case .delugeTorrents: return "water.waves"
        case .delugeServer: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard, .activity, .calendar, .settings: return .accentColor
        case .sonarrLibrary, .sonarrWanted, .sonarrHistory: return Theme.sonarr
        case .radarrLibrary, .radarrWanted, .radarrHistory: return Theme.radarr
        case .jellyfinLibraries, .jellyfinBrowse: return Theme.jellyfin
        case .downloadQueue, .downloadHistory, .downloadStatus: return Theme.nzbget
        case .delugeTorrents, .delugeServer: return Theme.deluge
        }
    }

    /// Screens that benefit from live polling while visible.
    var wantsPolling: Bool {
        switch self {
        case .dashboard, .activity, .downloadQueue, .downloadStatus: return true
        case .delugeTorrents, .delugeServer: return true
        default: return false
        }
    }
}
