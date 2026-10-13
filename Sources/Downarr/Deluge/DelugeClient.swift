import Foundation

/// Deluge 2.x web client. Everything goes through `POST /json`; the web UI hands back a
/// `_session_id` cookie on `auth.login`, which URLSession's shared cookie storage then replays.
struct DelugeClient {
    let http: HTTPClient
    let password: String

    init(endpoint: ServiceEndpoint) throws {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("Deluge")
        }
        // Deluge's web UI authenticates with a password only — any username is ignored.
        password = endpoint.password
        http = HTTPClient(baseURL: base, basePath: "", headers: [:])
    }

    private struct RPCRequest: Encodable {
        var method: String
        var params: [JSONValue]
        var id: Int
    }

    private struct RPCResponse<T: Decodable>: Decodable {
        var result: T?
        var error: RPCError?
    }

    private struct RPCError: Decodable {
        var message: String?
        var code: Int?
    }

    /// Deluge returns `{"error": {"code": 1, "message": "Not authenticated"}}` once the session
    /// cookie lapses, which is the signal to log in again.
    struct NotAuthenticated: Error {}

    @discardableResult
    func call<T: Decodable>(_ method: String, _ params: [JSONValue] = [],
                            as type: T.Type = T.self) async throws -> T? {
        let body = try Coders.encoder.encode(
            RPCRequest(method: method, params: params, id: Int(Date().timeIntervalSince1970 * 1000) % 100_000))
        let data = try await http.data("POST", "/json", body: body)
        let decoded: RPCResponse<T>
        do {
            decoded = try Coders.decoder.decode(RPCResponse<T>.self, from: data)
        } catch {
            throw APIError.decoding("\(method): \(error)")
        }
        if let error = decoded.error {
            if error.code == 1 { throw NotAuthenticated() }
            throw APIError.transport("Deluge \(method) failed: \(error.message ?? "code \(error.code ?? -1)")")
        }
        return decoded.result
    }

    /// Runs `work`, logging in once if the session has expired.
    func authenticated<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch is NotAuthenticated {
            guard try await login() else {
                throw APIError.transport("Deluge rejected the password")
            }
            return try await work()
        }
    }

    // MARK: Session

    @discardableResult
    func login() async throws -> Bool {
        let ok: Bool? = try await call("auth.login", [.string(password)])
        guard ok == true else { return false }
        // A fresh web session is not necessarily attached to the daemon yet.
        if try await isConnected() == false { try await connectFirstHost() }
        return true
    }

    func isConnected() async throws -> Bool {
        (try await call("web.connected", as: Bool.self)) ?? false
    }

    /// `web.get_hosts` → `[[id, host, port, username], …]`
    func connectFirstHost() async throws {
        guard let hosts: [[JSONValue]] = try await call("web.get_hosts"),
              let first = hosts.first, let id = first.first?.stringValue else { return }
        _ = try await call("web.connect", [.string(id)], as: JSONValue.self)
    }

    func version() async throws -> String? {
        try await call("daemon.get_version", as: String.self)
    }

    // MARK: Reads

    static let torrentKeys = [
        "name", "state", "progress", "total_size", "total_wanted", "total_done", "total_uploaded",
        "download_payload_rate", "upload_payload_rate", "eta", "ratio", "label", "save_path",
        "num_seeds", "num_peers", "total_seeds", "total_peers", "time_added", "completed_time",
        "tracker_host", "tracker_status", "is_finished", "active_time", "seeding_time", "queue",
        "max_download_speed", "distributed_copies", "message",
    ]

    func updateUI() async throws -> DelugeUpdateUI {
        let result: DelugeUpdateUI? = try await call("web.update_ui", [
            .array(Self.torrentKeys.map { .string($0) }),
            .object([:]),
        ])
        guard let result else { throw APIError.decoding("web.update_ui returned nothing") }
        return result
    }

    func labels() async throws -> [String] {
        (try await call("label.get_labels", as: [String].self)) ?? []
    }

    func enabledPlugins() async throws -> [String] {
        (try await call("core.get_enabled_plugins", as: [String].self)) ?? []
    }

    func configValues(_ keys: [String]) async throws -> [String: JSONValue] {
        (try await call("core.get_config_values",
                        [.array(keys.map { .string($0) })],
                        as: [String: JSONValue].self)) ?? [:]
    }

    // MARK: Torrent actions

    private func ids(_ hashes: [String]) -> JSONValue {
        .array(hashes.map { .string($0) })
    }

    func pause(_ hashes: [String]) async throws {
        _ = try await call("core.pause_torrents", [ids(hashes)], as: JSONValue.self)
    }

    func resume(_ hashes: [String]) async throws {
        _ = try await call("core.resume_torrents", [ids(hashes)], as: JSONValue.self)
    }

    func remove(_ hashes: [String], deleteData: Bool) async throws {
        _ = try await call("core.remove_torrents", [ids(hashes), .bool(deleteData)], as: JSONValue.self)
    }

    func forceRecheck(_ hashes: [String]) async throws {
        _ = try await call("core.force_recheck", [ids(hashes)], as: JSONValue.self)
    }

    enum QueueMove: String {
        case top = "core.queue_top"
        case up = "core.queue_up"
        case down = "core.queue_down"
        case bottom = "core.queue_bottom"
    }

    func queueMove(_ hashes: [String], _ move: QueueMove) async throws {
        _ = try await call(move.rawValue, [ids(hashes)], as: JSONValue.self)
    }

    func setTorrentOptions(_ hashes: [String], _ options: [String: JSONValue]) async throws {
        _ = try await call("core.set_torrent_options", [ids(hashes), .object(options)], as: JSONValue.self)
    }

    func moveStorage(_ hashes: [String], to path: String) async throws {
        _ = try await call("core.move_storage", [ids(hashes), .string(path)], as: JSONValue.self)
    }

    func setLabel(_ hash: String, label: String) async throws {
        _ = try await call("label.set_torrent", [.string(hash), .string(label)], as: JSONValue.self)
    }

    func addLabel(_ label: String) async throws {
        _ = try await call("label.add", [.string(label)], as: JSONValue.self)
    }

    // MARK: Adding

    func addMagnet(_ uri: String, options: [String: JSONValue]) async throws -> String? {
        try await call("core.add_torrent_magnet", [.string(uri), .object(options)], as: String.self)
    }

    func addURL(_ url: String, options: [String: JSONValue]) async throws -> String? {
        try await call("core.add_torrent_url", [.string(url), .object(options)], as: String.self)
    }

    // MARK: Session-wide

    func pauseSession() async throws {
        _ = try await call("core.pause_session", as: JSONValue.self)
    }

    func resumeSession() async throws {
        _ = try await call("core.resume_session", as: JSONValue.self)
    }

    /// Speed caps are KiB/s; -1 is unlimited.
    func setSpeedLimits(download: Double?, upload: Double?) async throws {
        var config: [String: JSONValue] = [:]
        if let download { config["max_download_speed"] = .number(download) }
        if let upload { config["max_upload_speed"] = .number(upload) }
        guard !config.isEmpty else { return }
        _ = try await call("core.set_config", [.object(config)], as: JSONValue.self)
    }
}
