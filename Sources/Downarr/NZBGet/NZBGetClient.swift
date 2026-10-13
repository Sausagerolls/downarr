import Foundation

/// NZBGet JSON-RPC 1.1 client (HTTP Basic auth, single `/jsonrpc` endpoint).
struct NZBGetClient {
    let http: HTTPClient

    init(endpoint: ServiceEndpoint) throws {
        guard let base = endpoint.baseURL, !endpoint.host.isEmpty else {
            throw APIError.notConfigured("NZBGet")
        }
        var headers: [String: String] = [:]
        if let auth = endpoint.basicAuthHeader { headers["Authorization"] = auth }
        http = HTTPClient(baseURL: base, basePath: "", headers: headers)
    }

    private struct RPCRequest: Encodable {
        var version = "1.1"
        var id = 1
        var method: String
        var params: [JSONValue]
    }

    private struct RPCResponse<T: Decodable>: Decodable {
        var result: T?
        var error: RPCError?
    }

    private struct RPCError: Decodable {
        var code: Int?
        var message: String?
    }

    func call<T: Decodable>(_ method: String, _ params: [JSONValue] = [], as type: T.Type = T.self) async throws -> T {
        let body = try Coders.encoder.encode(RPCRequest(method: method, params: params))
        let data = try await http.data("POST", "/jsonrpc", body: body)
        let decoded: RPCResponse<T>
        do {
            decoded = try Coders.decoder.decode(RPCResponse<T>.self, from: data)
        } catch {
            throw APIError.decoding("\(method): \(error)")
        }
        if let error = decoded.error {
            throw APIError.transport("NZBGet \(method) failed: \(error.message ?? "code \(error.code ?? -1)")")
        }
        guard let result = decoded.result else {
            throw APIError.decoding("\(method) returned no result")
        }
        return result
    }

    // MARK: Reads
    func version() async throws -> String { try await call("version") }
    func status() async throws -> NZBGetStatus { try await call("status") }
    func groups() async throws -> [NZBGetGroup] { try await call("listgroups", [.number(0)]) }
    func history(hidden: Bool = false) async throws -> [NZBGetHistoryItem] {
        try await call("history", [.bool(hidden)])
    }

    /// `[{Name:…, Value:…}]` — used for categories and paths.
    func config() async throws -> [[String: JSONValue]] { try await call("config") }

    func categories() async throws -> [String] {
        let entries = try await config()
        return entries.compactMap { entry -> (Int, String)? in
            guard let name = entry["Name"]?.stringValue,
                  name.hasPrefix("Category"), name.hasSuffix(".Name"),
                  let value = entry["Value"]?.stringValue, !value.isEmpty else { return nil }
            let digits = name.dropFirst("Category".count).prefix { $0.isNumber }
            return (Int(digits) ?? 0, value)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    func log(lines: Int = 100) async throws -> [[String: JSONValue]] {
        try await call("log", [.number(0), .number(Double(lines))])
    }

    // MARK: Global controls
    @discardableResult func pauseDownload() async throws -> Bool { try await call("pausedownload") }
    @discardableResult func resumeDownload() async throws -> Bool { try await call("resumedownload") }
    @discardableResult func pausePost() async throws -> Bool { try await call("pausepost") }
    @discardableResult func resumePost() async throws -> Bool { try await call("resumepost") }
    @discardableResult func pauseScan() async throws -> Bool { try await call("pausescan") }
    @discardableResult func resumeScan() async throws -> Bool { try await call("resumescan") }
    @discardableResult func setRate(kilobytesPerSecond: Int) async throws -> Bool {
        try await call("rate", [.number(Double(kilobytesPerSecond))])
    }
    @discardableResult func scan() async throws -> Bool { try await call("scan") }
    @discardableResult func reload() async throws -> Bool { try await call("reload") }
    @discardableResult func shutdown() async throws -> Bool { try await call("shutdown") }

    // MARK: Queue edits
    @discardableResult
    func editQueue(_ command: String, offset: Int = 0, text: String = "", ids: [Int]) async throws -> Bool {
        try await call("editqueue", [
            .string(command),
            .number(Double(offset)),
            .string(text),
            .array(ids.map { .number(Double($0)) }),
        ])
    }

    func pause(ids: [Int]) async throws { try await editQueue("GroupPause", ids: ids) }
    func resume(ids: [Int]) async throws { try await editQueue("GroupResume", ids: ids) }
    func delete(ids: [Int], deleteFiles: Bool) async throws {
        try await editQueue(deleteFiles ? "GroupFinalDelete" : "GroupDelete", ids: ids)
    }
    func moveTop(ids: [Int]) async throws { try await editQueue("GroupMoveTop", ids: ids) }
    func moveBottom(ids: [Int]) async throws { try await editQueue("GroupMoveBottom", ids: ids) }
    func move(ids: [Int], offset: Int) async throws {
        try await editQueue("GroupMoveOffset", offset: offset, ids: ids)
    }
    func setPriority(ids: [Int], priority: Int) async throws {
        try await editQueue("GroupSetPriority", text: String(priority), ids: ids)
    }
    func setCategory(ids: [Int], category: String) async throws {
        try await editQueue("GroupSetCategory", text: category, ids: ids)
    }

    // MARK: History edits
    func historyDelete(ids: [Int]) async throws { try await editQueue("HistoryDelete", ids: ids) }
    func historyFinalDelete(ids: [Int]) async throws { try await editQueue("HistoryFinalDelete", ids: ids) }
    func historyRedownload(ids: [Int]) async throws { try await editQueue("HistoryRedownload", ids: ids) }
    func historyReturn(ids: [Int]) async throws { try await editQueue("HistoryReturn", ids: ids) }
    func historyMarkGood(ids: [Int]) async throws { try await editQueue("HistoryMarkGood", ids: ids) }
    func historyMarkBad(ids: [Int]) async throws { try await editQueue("HistoryMarkBad", ids: ids) }

    // MARK: Add
    @discardableResult
    func appendURL(_ url: String, category: String, priority: Int, paused: Bool, addToTop: Bool) async throws -> Int {
        try await call("append", [
            .string(""),            // NZBFilename — empty means "content is a URL"
            .string(url),
            .string(category),
            .number(Double(priority)),
            .bool(addToTop),
            .bool(paused),
            .string(""),            // DupeKey
            .number(0),             // DupeScore
            .string("SCORE"),       // DupeMode
            .array([]),             // PPParameters
        ])
    }
}
