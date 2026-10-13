import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var radarr: RadarrStore
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore

    @State private var tests: [String: String] = [:]
    @State private var testing: Set<String> = []
    @State private var cacheSize: Int64 = 0
    @State private var showReset = false

    var body: some View {
        PageScaffold(title: "Settings", subtitle: "Connections are stored on this Mac only") {
            Button {
                Task { await app.refreshEverything() }
            } label: {
                Label("Reload all data", systemImage: "arrow.clockwise")
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    serviceCard(
                        name: "Sonarr", tint: Theme.sonarr, icon: "tv",
                        endpoint: Binding(get: { config.config.sonarr },
                                          set: { config.config.sonarr = $0 }),
                        usesAPIKey: true,
                        status: sonarr.status?.version.map { "Connected · v\($0)" })

                    serviceCard(
                        name: "Radarr", tint: Theme.radarr, icon: "film",
                        endpoint: Binding(get: { config.config.radarr },
                                          set: { config.config.radarr = $0 }),
                        usesAPIKey: true,
                        status: radarr.status?.version.map { "Connected · v\($0)" })

                    serviceCard(
                        name: "Jellyfin", tint: Theme.jellyfin, icon: "play.tv",
                        endpoint: Binding(get: { config.config.jellyfin },
                                          set: { config.config.jellyfin = $0 }),
                        usesAPIKey: false,
                        status: jellyfin.systemInfo.map { "Connected · \($0.ServerName ?? "server") v\($0.Version ?? "")" },
                        extra: {
                            HStack(spacing: 8) {
                                Button("Sign in again") {
                                    Task {
                                        app.applyConfiguration()
                                        if await jellyfin.authenticate() {
                                            await jellyfin.loadOverview(force: true)
                                        }
                                    }
                                }
                                .controlSize(.small)
                                if jellyfin.isAuthenticated {
                                    Pill(text: "Token stored", tint: Theme.positive, icon: "checkmark.seal.fill")
                                } else {
                                    Pill(text: "Not signed in", tint: Theme.warning)
                                }
                                Spacer()
                            }
                        })

                    serviceCard(
                        name: "NZBGet", tint: Theme.nzbget, icon: "arrow.down.circle",
                        endpoint: Binding(get: { config.config.nzbget },
                                          set: { config.config.nzbget = $0 }),
                        usesAPIKey: false,
                        status: nzbget.version.map { "Connected · v\($0)" })

                    serviceCard(
                        name: "Deluge", tint: Theme.deluge, icon: "water.waves",
                        endpoint: Binding(get: { config.config.deluge },
                                          set: { config.config.deluge = $0 }),
                        usesAPIKey: false,
                        status: deluge.version.map { "Connected · v\($0)" },
                        extra: {
                            Text("Deluge's web UI authenticates with a password only — the username is ignored.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        })

                    appearanceCard
                    maintenanceCard
                }
                .padding(18)
            }
        }
        .task { cacheSize = await ImageLoader.shared.diskSize() }
        .alert("Reset all settings?", isPresented: $showReset) {
            Button("Reset", role: .destructive) {
                config.resetToDefaults()
                app.applyConfiguration()
                Task { await app.refreshEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Connections go back to the values Downarr shipped with.")
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func serviceCard<Extra: View>(name: String,
                                          tint: Color,
                                          icon: String,
                                          endpoint: Binding<ServiceEndpoint>,
                                          usesAPIKey: Bool,
                                          status: String?,
                                          @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(name).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let status {
                    Pill(text: status, tint: Theme.positive, icon: "checkmark.circle.fill")
                } else {
                    Pill(text: "Not connected", tint: Theme.danger)
                }
            }

            HStack(spacing: 8) {
                labelledField("Host", text: endpoint.host, width: 170)
                labelledField("Port", text: Binding(
                    get: { String(endpoint.wrappedValue.port) },
                    set: { endpoint.wrappedValue.port = Int($0) ?? endpoint.wrappedValue.port }
                ), width: 70)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheme").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                    Picker("", selection: endpoint.scheme) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                Spacer()
            }

            if usesAPIKey {
                labelledField("API key", text: endpoint.apiKey, width: 340, monospaced: true)
            } else {
                HStack(spacing: 8) {
                    labelledField("Username", text: endpoint.username, width: 170)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Password").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                        SecureField("", text: endpoint.password).frame(width: 170)
                    }
                    Spacer()
                }
            }

            extra()

            HStack(spacing: 8) {
                Button("Test connection") {
                    Task { await test(name) }
                }
                .controlSize(.small)
                .disabled(testing.contains(name))
                if testing.contains(name) {
                    ProgressView().controlSize(.small)
                }
                if let result = tests[name] {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("OK") ? Theme.positive : Theme.danger)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                Link("Open web UI", destination: URL(string: endpoint.wrappedValue.displayAddress)
                     ?? URL(string: "http://localhost")!)
                    .font(.caption)
            }
        }
        .textFieldStyle(.roundedBorder)
        .card()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behaviour").font(.system(size: 14, weight: .semibold))
            HStack {
                Text("Live refresh interval")
                    .font(.caption)
                    .frame(width: 160, alignment: .leading)
                Slider(value: Binding(get: { config.config.refreshInterval },
                                      set: { config.config.refreshInterval = $0 }),
                       in: 2...30, step: 1)
                    .frame(width: 220)
                Text("\(Int(config.config.refreshInterval))s")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("Applies to the download queue, activity and dashboard while they are open.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance").font(.system(size: 14, weight: .semibold))
            HStack(spacing: 10) {
                Text("Poster cache: \(Fmt.bytes(cacheSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear cache") {
                    Task {
                        await ImageLoader.shared.purgeDisk()
                        cacheSize = await ImageLoader.shared.diskSize()
                    }
                }
                .controlSize(.small)
                Spacer()
                Button("Reset settings…", role: .destructive) { showReset = true }
                    .controlSize(.small)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                KeyValueRow(key: "Device ID", value: config.config.jellyfinDeviceID)
                KeyValueRow(key: "Config location", value: "UserDefaults · com.jakewatts.downarr")
            }
        }
        .card()
    }

    private func labelledField(_ label: String, text: Binding<String>,
                               width: CGFloat, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
            TextField("", text: text)
                .font(monospaced ? .system(size: 11, design: .monospaced) : nil)
                .frame(width: width)
        }
    }

    // MARK: Tests

    private func test(_ name: String) async {
        testing.insert(name)
        defer { testing.remove(name) }
        app.applyConfiguration()
        do {
            switch name {
            case "Sonarr":
                let client = try SonarrClient(endpoint: config.config.sonarr)
                let status = try await client.status()
                tests[name] = "OK · \(status.appName ?? "Sonarr") \(status.version ?? "")"
                await sonarr.loadAll(force: true)
            case "Radarr":
                let client = try RadarrClient(endpoint: config.config.radarr)
                let status = try await client.status()
                tests[name] = "OK · \(status.appName ?? "Radarr") \(status.version ?? "")"
                await radarr.loadAll(force: true)
            case "Jellyfin":
                let result = try await JellyfinClient.authenticate(endpoint: config.config.jellyfin,
                                                                   deviceID: config.config.jellyfinDeviceID)
                if let token = result.AccessToken, let user = result.User {
                    config.config.jellyfinToken = token
                    config.config.jellyfinUserID = user.Id
                    app.applyConfiguration()
                    tests[name] = "OK · signed in as \(user.Name ?? "user")"
                    await jellyfin.loadOverview(force: true)
                } else {
                    tests[name] = "Failed · no token returned"
                }
            case "NZBGet":
                let client = try NZBGetClient(endpoint: config.config.nzbget)
                let version = try await client.version()
                tests[name] = "OK · NZBGet \(version)"
                await nzbget.load(force: true)
            case "Deluge":
                let client = try DelugeClient(endpoint: config.config.deluge)
                guard try await client.login() else {
                    tests[name] = "Failed · Deluge rejected the password"
                    break
                }
                let version = (try? await client.version()) ?? "?"
                let connected = (try? await client.isConnected()) ?? false
                tests[name] = connected
                    ? "OK · Deluge \(version ?? "?")"
                    : "Signed in, but the web UI is not connected to the daemon"
                await deluge.load(force: true)
            default:
                break
            }
        } catch {
            tests[name] = "Failed · " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
