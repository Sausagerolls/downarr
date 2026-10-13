import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 226, max: 280)
        } detail: {
            DetailRouter(selection: app.selection ?? .dashboard)
                .frame(minWidth: 640)
        }
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                ToastOverlay(toast: toast)
                    .onTapGesture { toasts.dismiss() }
            }
        }
        .animation(.easeOut(duration: 0.2), value: toasts.current)
        .task {
            await app.bootstrap()
        }
        .onChange(of: app.selection) { _, new in
            // Only poll NZBGet while a screen that shows live transfer state is open.
            if new?.wantsPolling == true {
                nzbget.startPolling(interval: app.config.config.refreshInterval)
                deluge.startPolling(interval: app.config.config.refreshInterval)
            } else {
                nzbget.stopPolling()
                deluge.stopPolling()
            }
        }
        .onAppear {
            if (app.selection ?? .dashboard).wantsPolling {
                nzbget.startPolling(interval: app.config.config.refreshInterval)
                deluge.startPolling(interval: app.config.config.refreshInterval)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var radarr: RadarrStore
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore

    var body: some View {
        List(selection: $app.selection) {
            Section("Overview") {
                row(.dashboard)
                row(.activity, badge: activeCount)
                row(.calendar)
            }

            Section {
                row(.sonarrLibrary, badge: sonarr.series.isEmpty ? nil : sonarr.series.count)
                row(.sonarrWanted, badge: sonarr.missingEpisodeCount > 0 ? sonarr.missingEpisodeCount : nil)
                row(.sonarrHistory)
            } header: {
                serviceHeader("Sonarr", tint: Theme.sonarr,
                              ok: sonarr.status != nil, detail: sonarr.status?.version)
            }

            Section {
                row(.radarrLibrary, badge: radarr.movies.isEmpty ? nil : radarr.movies.count)
                row(.radarrWanted, badge: radarr.missingCount > 0 ? radarr.missingCount : nil)
                row(.radarrHistory)
            } header: {
                serviceHeader("Radarr", tint: Theme.radarr,
                              ok: radarr.status != nil, detail: radarr.status?.version)
            }

            Section {
                row(.jellyfinLibraries, badge: jellyfin.libraries.isEmpty ? nil : jellyfin.libraries.count)
                row(.jellyfinBrowse)
            } header: {
                serviceHeader("Jellyfin", tint: Theme.jellyfin,
                              ok: jellyfin.systemInfo != nil, detail: jellyfin.systemInfo?.Version)
            }

            Section {
                row(.downloadQueue, badge: nzbget.groups.isEmpty ? nil : nzbget.groups.count)
                row(.downloadHistory)
                row(.downloadStatus)
            } header: {
                serviceHeader("NZBGet", tint: Theme.nzbget,
                              ok: nzbget.status != nil, detail: nzbget.version)
            }

            Section {
                row(.delugeTorrents, badge: deluge.torrents.isEmpty ? nil : deluge.torrents.count)
                row(.delugeServer)
            } header: {
                serviceHeader("Deluge", tint: Theme.deluge,
                              ok: deluge.stats != nil, detail: deluge.version)
            }

            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            transferFooter
        }
    }

    private var activeCount: Int? {
        let count = sonarr.queue.count + radarr.queue.count
        return count > 0 ? count : nil
    }

    /// Both download clients contribute to the throughput shown in the footer.
    private var combinedRate: Int { nzbget.downloadRate + deluge.downloadRate }

    private func row(_ item: SidebarItem, badge: Int? = nil) -> some View {
        NavigationLink(value: item) {
            Label {
                HStack {
                    Text(item.title)
                    if let badge {
                        Spacer()
                        Text(badge.formatted())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            } icon: {
                Image(systemName: item.icon).foregroundStyle(item.tint)
            }
        }
        .tag(item)
    }

    private func serviceHeader(_ name: String, tint: Color, ok: Bool, detail: String?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Theme.positive : Theme.danger)
                .frame(width: 6, height: 6)
            Text(name)
            if let detail {
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var footerDetail: String {
        var parts: [String] = []
        if !nzbget.groups.isEmpty { parts.append("\(nzbget.groups.count) usenet") }
        let activeTorrents = deluge.downloadingCount
        if activeTorrents > 0 { parts.append("\(activeTorrents) torrent\(activeTorrents == 1 ? "" : "s")") }
        if parts.isEmpty { return "Queues empty" }
        let left = nzbget.remainingBytes + deluge.remainingBytes
        return parts.joined(separator: " · ") + " · " + Fmt.bytes(left) + " left"
    }

    private var transferFooter: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: nzbget.isPaused ? "pause.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(nzbget.isPaused ? Theme.warning : Theme.nzbget)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nzbget.isPaused && combinedRate == 0 ? "Paused" : Fmt.rate(combinedRate))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(footerDetail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await nzbget.togglePause() }
                } label: {
                    Image(systemName: nzbget.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help(nzbget.isPaused ? "Resume downloads" : "Pause downloads")
                .disabled(!nzbget.isConfigured)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)  // the sidebar list scrolls underneath this inset
    }
}

// MARK: - Routing

struct DetailRouter: View {
    let selection: SidebarItem

    var body: some View {
        switch selection {
        case .dashboard:
            NavigationStack { DashboardView() }
        case .activity:
            NavigationStack { ActivityView() }
        case .calendar:
            NavigationStack { CalendarView() }
        case .sonarrLibrary:
            NavigationStack { SonarrLibraryView() }
        case .sonarrWanted:
            NavigationStack { SonarrWantedView() }
        case .sonarrHistory:
            NavigationStack { SonarrHistoryView() }
        case .radarrLibrary:
            NavigationStack { RadarrLibraryView() }
        case .radarrWanted:
            NavigationStack { RadarrWantedView() }
        case .radarrHistory:
            NavigationStack { RadarrHistoryView() }
        case .jellyfinLibraries:
            NavigationStack { JellyfinLibrariesView() }
        case .jellyfinBrowse:
            NavigationStack { JellyfinBrowseView() }
        case .downloadQueue:
            NavigationStack { NZBGetQueueView() }
        case .downloadHistory:
            NavigationStack { NZBGetHistoryView() }
        case .downloadStatus:
            NavigationStack { NZBGetStatusView() }
        case .delugeTorrents:
            NavigationStack { DelugeTorrentsView() }
        case .delugeServer:
            NavigationStack { DelugeServerView() }
        case .settings:
            NavigationStack { SettingsScreen() }
        }
    }
}

/// Shared page chrome: title, optional subtitle, trailing controls, scrollable body.
struct PageScaffold<Toolbar: View, Content: View>: View {
    let title: String
    var subtitle: String?
    var error: String?
    var onRetry: (() -> Void)?
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                toolbar()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .hairline()

            if let error {
                ErrorBanner(message: error, retry: onRetry)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PageScaffold where Toolbar == EmptyView {
    init(title: String, subtitle: String? = nil, error: String? = nil,
         onRetry: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, error: error, onRetry: onRetry,
                  toolbar: { EmptyView() }, content: content)
    }
}
