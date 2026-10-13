import Foundation

enum APIError: LocalizedError {
    case notConfigured(String)
    case badURL
    case status(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return "\(s) is not configured."
        case .badURL: return "Malformed request URL."
        case .status(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(trimmed.prefix(300))"
        case .decoding(let s): return "Could not read the response: \(s)"
        case .transport(let s): return s
        }
    }

    var isUnauthorized: Bool {
        if case .status(let code, _) = self { return code == 401 || code == 403 }
        return false
    }
}

/// Shared JSON coders with the lenient date handling the *arr apps and Jellyfin need.
enum Coders {
    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        if let d = iso8601Fractional.date(from: raw) { return d }
        if let d = iso8601.date(from: raw) { return d }
        if let d = dayOnly.date(from: raw) { return d }
        // Jellyfin sometimes emits more than 3 fractional digits.
        if let dot = raw.firstIndex(of: "."), raw.hasSuffix("Z") {
            let head = String(raw[raw.startIndex..<dot])
            if let d = iso8601.date(from: head + "Z") { return d }
        }
        return nil
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) { return date }
            return Date.distantPast
        }
        return d
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(iso8601.string(from: date))
        }
        return e
    }
}

/// Thin async wrapper around URLSession with per-service base URL and headers.
struct HTTPClient {
    var baseURL: URL
    var basePath: String = ""
    var headers: [String: String] = [:]
    var defaultQuery: [String: String] = [:]

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 120
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 8
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func url(_ path: String, query: [String: String?] = [:]) -> URL? {
        let full = basePath + (path.hasPrefix("/") ? path : "/" + path)
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(""),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.path = full
        var items = defaultQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
        for (k, v) in query {
            if let v, !v.isEmpty { items.append(URLQueryItem(name: k, value: v)) }
        }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.url
    }

    private func request(_ method: String, _ path: String,
                         query: [String: String?] = [:],
                         body: Data? = nil,
                         contentType: String = "application/json") -> URLRequest? {
        guard let u = url(path, query: query) else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            r.httpBody = body
            r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    @discardableResult
    func data(_ method: String, _ path: String,
              query: [String: String?] = [:],
              body: Data? = nil,
              contentType: String = "application/json") async throws -> Data {
        guard let req = request(method, path, query: query, body: body, contentType: contentType) else {
            throw APIError.badURL
        }
        do {
            let (data, response) = try await Self.session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("No HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.status(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await data("GET", path, query: query)
        return try decode(data)
    }

    func post<T: Decodable>(_ path: String, query: [String: String?] = [:],
                            body: Encodable? = nil, as type: T.Type = T.self) async throws -> T {
        let data = try await data("POST", path, query: query, body: try encodeBody(body))
        return try decode(data)
    }

    @discardableResult
    func postVoid(_ path: String, query: [String: String?] = [:], body: Encodable? = nil) async throws -> Data {
        try await data("POST", path, query: query, body: try encodeBody(body))
    }

    func put<T: Decodable>(_ path: String, query: [String: String?] = [:],
                           body: Encodable? = nil, as type: T.Type = T.self) async throws -> T {
        let data = try await data("PUT", path, query: query, body: try encodeBody(body))
        return try decode(data)
    }

    @discardableResult
    func delete(_ path: String, query: [String: String?] = [:]) async throws -> Data {
        try await data("DELETE", path, query: query)
    }

    private func encodeBody(_ body: Encodable?) throws -> Data? {
        guard let body else { return nil }
        return try Coders.encoder.encode(body)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try Coders.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(T.self): \(error)")
        }
    }
}

struct EmptyResponse: Codable {}

/// Raw JSON value, for the places where a schema is not worth modelling (Jellyfin DTO round-trips).
indirect enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v):
            if v == v.rounded(), abs(v) < 9e15 { try c.encode(Int(v)) } else { try c.encode(v) }
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}
