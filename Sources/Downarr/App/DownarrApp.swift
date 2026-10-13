import SwiftUI

@main
struct DownarrApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.config)
                .environmentObject(app.toasts)
                .environmentObject(app.sonarr)
                .environmentObject(app.radarr)
                .environmentObject(app.jellyfin)
                .environmentObject(app.nzbget)
                .environmentObject(app.deluge)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Everything") {
                    Task { await app.refreshEverything() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("Go") {
                jump("Dashboard", .dashboard, "1")
                jump("Activity", .activity, "2")
                jump("Calendar", .calendar, "3")
                Divider()
                jump("Series", .sonarrLibrary, "4")
                jump("Movies", .radarrLibrary, "5")
                Divider()
                jump("Jellyfin Libraries", .jellyfinLibraries, "6")
                jump("Browse Jellyfin", .jellyfinBrowse, "7")
                Divider()
                jump("Download Queue", .downloadQueue, "8")
                jump("Download History", .downloadHistory, "9")
                jump("NZBGet Server", .downloadStatus, "0")
                Divider()
                jump("Torrents", .delugeTorrents, "d")
                Button("Deluge Server") { app.selection = .delugeServer }
                Divider()
                jump("Settings", .settings, ",")
            }

            CommandGroup(replacing: .help) {
                Button("Open Sonarr in Browser") { openWebUI(app.config.config.sonarr) }
                Button("Open Radarr in Browser") { openWebUI(app.config.config.radarr) }
                Button("Open Jellyfin in Browser") { openWebUI(app.config.config.jellyfin) }
                Button("Open NZBGet in Browser") { openWebUI(app.config.config.nzbget) }
                Button("Open Deluge in Browser") { openWebUI(app.config.config.deluge) }
            }
        }
    }

    /// A host cleared in Settings makes `displayAddress` unparseable, so never force-unwrap it.
    private func openWebUI(_ endpoint: ServiceEndpoint) {
        guard let url = URL(string: endpoint.displayAddress) else { return }
        NSWorkspace.shared.open(url)
    }

    private func jump(_ title: String, _ item: SidebarItem, _ key: KeyEquivalent) -> some View {
        Button(title) { app.selection = item }
            .keyboardShortcut(key, modifiers: .command)
    }
}
