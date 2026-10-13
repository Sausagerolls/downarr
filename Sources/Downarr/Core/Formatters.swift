import Foundation

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useTB, .useKB]
        return f
    }()

    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return byteFormatter.string(fromByteCount: value)
    }

    static func bytes(_ value: Int?) -> String { bytes(value.map(Int64.init)) }

    static func megabytes(_ mb: Int?) -> String {
        guard let mb else { return "—" }
        return bytes(Int64(mb) * 1_048_576)
    }

    static func rate(_ bytesPerSecond: Int?) -> String {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return "0 MB/s" }
        return byteFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func date(_ d: Date?) -> String {
        guard let d, d > Date.distantPast, d.timeIntervalSince1970 > 0 else { return "—" }
        return shortDate.string(from: d)
    }

    static func dateTime(_ d: Date?) -> String {
        guard let d, d > Date.distantPast, d.timeIntervalSince1970 > 0 else { return "—" }
        return dateTime.string(from: d)
    }

    static func ago(_ d: Date?) -> String {
        guard let d, d > Date.distantPast, d.timeIntervalSince1970 > 0 else { return "—" }
        return relative.localizedString(for: d, relativeTo: Date())
    }

    /// Sonarr/Radarr "timeleft" comes as "HH:mm:ss" or "d.HH:mm:ss".
    static func timespan(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let parts = raw.split(separator: ".")
        var days = 0
        var clock = raw
        if parts.count == 2, let d = Int(parts[0]) {
            days = d
            clock = String(parts[1])
        }
        let bits = clock.split(separator: ":").compactMap { Int($0.prefix(2)) }
        guard bits.count >= 2 else { return raw }
        let h = bits[0], m = bits[1]
        if days > 0 { return "\(days)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        let s = bits.count > 2 ? bits[2] : 0
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    static func duration(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func minutes(_ mins: Int?) -> String {
        guard let mins, mins > 0 else { return "—" }
        return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
    }

    static func ticks(_ ticks: Int64?) -> String {
        guard let ticks, ticks > 0 else { return "—" }
        return minutes(Int(ticks / 600_000_000))
    }
}
