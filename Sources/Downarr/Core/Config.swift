import Foundation

/// Connection details for one backend service.
struct ServiceEndpoint: Codable, Equatable, Hashable {
    var scheme: String = "http"
    var host: String = ""
    var port: Int = 80
    var apiKey: String = ""
    var username: String = ""
    var password: String = ""
    var isEnabled: Bool = true

    var baseURL: URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host.trimmingCharacters(in: .whitespaces)
        comps.port = port
        comps.path = ""
        return comps.url
    }

    var displayAddress: String { "\(scheme)://\(host):\(port)" }

    var basicAuthHeader: String? {
        guard !username.isEmpty else { return nil }
        let raw = "\(username):\(password)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic " + data.base64EncodedString()
    }
}

/// Everything the app persists.
struct AppConfig: Codable, Equatable {
    // Standard ports, no hosts or credentials: the user fills these in under Settings.
    var sonarr = ServiceEndpoint(port: 8989)
    var radarr = ServiceEndpoint(port: 7878)
    var jellyfin = ServiceEndpoint(port: 8096)
    var nzbget = ServiceEndpoint(port: 6789)
    /// Deluge's web UI authenticates with a password only; the username is kept for reference.
    var deluge = ServiceEndpoint(port: 8112)

    /// Cached Jellyfin session so we don't re-authenticate on every launch.
    var jellyfinToken: String = ""
    var jellyfinUserID: String = ""
    var jellyfinDeviceID: String = ""

    var refreshInterval: Double = 5
    var posterQuality: Int = 500
    var preferListLayout: Bool = false
}

/// Single source of truth for configuration, persisted to UserDefaults.
///
/// Deliberately not the Keychain: the app is ad-hoc signed and rebuilt often, which invalidates
/// Keychain ACLs and produces authorisation prompts. This app never leaves the machine.
final class ConfigStore: ObservableObject {
    private static let key = "downarr.config.v1"

    @Published var config: AppConfig {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) ?? Self.legacyData(),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }
        if config.jellyfinDeviceID.isEmpty {
            config.jellyfinDeviceID = "downarr-" + UUID().uuidString.prefix(8)
        }
    }

    /// Settings saved under the old `local.downarr.Downarr` bundle ID. Readable only by unsandboxed
    /// builds; a sandboxed (App Store) build cannot see it and starts fresh.
    private static func legacyData() -> Data? {
        UserDefaults(suiteName: "local.downarr.Downarr")?.data(forKey: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    func resetToDefaults() {
        var fresh = AppConfig()
        fresh.jellyfinDeviceID = config.jellyfinDeviceID
        config = fresh
    }
}
