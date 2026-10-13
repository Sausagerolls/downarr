import Foundation
import SwiftUI

// Deluge 2.x speaks JSON-RPC over /json with snake_case keys, so the models mirror those names.

struct DelugeTorrent: Codable, Hashable, Identifiable {
    var hash: String = ""            // filled in from the dictionary key
    var name: String?
    var state: String?
    var progress: Double?            // 0...100
    var total_size: Int64?
    var total_wanted: Int64?
    var total_done: Int64?
    var total_uploaded: Int64?
    var download_payload_rate: Int?
    var upload_payload_rate: Int?
    var eta: Int?
    var ratio: Double?
    var label: String?
    var save_path: String?
    var num_seeds: Int?
    var num_peers: Int?
    var total_seeds: Int?
    var total_peers: Int?
    var time_added: Double?
    var completed_time: Double?
    var tracker_host: String?
    var tracker_status: String?
    var is_finished: Bool?
    var active_time: Int?
    var seeding_time: Int?
    var queue: Int?
    var max_download_speed: Double?
    var distributed_copies: Double?
    var message: String?


    // `hash` is the key of Deluge's torrent dictionary, not a field inside the object,
    // so it is filled in by the store and deliberately left out of the coding keys.
    enum CodingKeys: String, CodingKey {
        case name, state, progress, total_size, total_wanted,
             total_done, total_uploaded, download_payload_rate, upload_payload_rate, eta,
             ratio, label, save_path, num_seeds, num_peers,
             total_seeds, total_peers, time_added, completed_time, tracker_host,
             tracker_status, is_finished, active_time, seeding_time, queue,
             max_download_speed, distributed_copies, message
    }

    var id: String { hash }
    var title: String { name ?? hash }
    var fraction: Double { min(1, max(0, (progress ?? 0) / 100)) }
    var isPaused: Bool { (state ?? "") == "Paused" }
    var isSeeding: Bool { (state ?? "") == "Seeding" }
    var isDownloading: Bool { (state ?? "") == "Downloading" }
    var isError: Bool { (state ?? "") == "Error" }
    var isActive: Bool { (download_payload_rate ?? 0) > 0 || (upload_payload_rate ?? 0) > 0 }
    var addedDate: Date? { time_added.map { Date(timeIntervalSince1970: $0) } }
    var completedDate: Date? {
        guard let completed_time, completed_time > 0 else { return nil }
        return Date(timeIntervalSince1970: completed_time)
    }
    var remaining: Int64 { max(0, (total_wanted ?? 0) - (total_done ?? 0)) }

    var etaText: String {
        guard let eta, eta > 0 else { return is_finished == true ? "Done" : "—" }
        return Fmt.duration(eta)
    }

    var seedsPeers: String {
        "\(num_seeds ?? 0)/\(max(0, total_seeds ?? 0)) · \(num_peers ?? 0)/\(max(0, total_peers ?? 0))"
    }

    var statusTint: Color {
        switch state ?? "" {
        case "Downloading": return Theme.deluge
        case "Seeding": return Theme.positive
        case "Paused": return Theme.warning
        case "Error": return Theme.danger
        case "Checking", "Allocating", "Moving": return Theme.jellyfin
        case "Queued": return Theme.neutral
        default: return Theme.neutral
        }
    }

    var statusIcon: String {
        switch state ?? "" {
        case "Downloading": return "arrow.down.circle.fill"
        case "Seeding": return "arrow.up.circle.fill"
        case "Paused": return "pause.circle.fill"
        case "Error": return "exclamationmark.triangle.fill"
        case "Checking", "Allocating", "Moving": return "gearshape.2.fill"
        default: return "circle.fill"
        }
    }

    /// Deluge reports "OK" as the message for healthy torrents; only surface real problems.
    var problem: String? {
        guard let message, !message.isEmpty, message != "OK" else {
            let tracker = tracker_status ?? ""
            return tracker.lowercased().contains("error") ? tracker : nil
        }
        return message
    }
}

struct DelugeStats: Codable, Hashable {
    var download_rate: Double?
    var upload_rate: Double?
    var download_protocol_rate: Double?
    var upload_protocol_rate: Double?
    var max_download: Double?
    var max_upload: Double?
    var num_connections: Int?
    var max_num_connections: Int?
    var dht_nodes: Int?
    var free_space: Int64?
    var has_incoming_connections: JSONValue?   // int on some builds, bool on others
    var external_ip: String?

    var downloadRate: Int { Int(download_rate ?? 0) }
    var uploadRate: Int { Int(upload_rate ?? 0) }
    /// Deluge stores speed caps in KiB/s, with -1 meaning unlimited.
    var downloadLimitKiB: Double { max_download ?? -1 }
    var uploadLimitKiB: Double { max_upload ?? -1 }
    var acceptsIncoming: Bool {
        if let value = has_incoming_connections?.intValue { return value != 0 }
        return has_incoming_connections?.boolValue ?? false
    }
}

struct DelugeUpdateUI: Codable {
    var connected: Bool?
    var torrents: [String: DelugeTorrent]?
    var stats: DelugeStats?
    /// `{"state": [["All", 23], ["Downloading", 1], …], "label": [...]}`
    var filters: [String: [[JSONValue]]]?
}

/// One row of a Deluge filter bucket, e.g. state "Downloading" with 1 torrent.
struct DelugeFilterCount: Identifiable, Hashable {
    var name: String
    var count: Int
    var id: String { name }

    static func parse(_ raw: [[JSONValue]]?) -> [DelugeFilterCount] {
        (raw ?? []).compactMap { pair in
            guard pair.count >= 2, let name = pair[0].stringValue else { return nil }
            return DelugeFilterCount(name: name, count: pair[1].intValue ?? 0)
        }
    }
}

enum DelugeSortKey: String, CaseIterable, Identifiable {
    case queue, name, progress, size, ratio, added, downRate, upRate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .queue: return "Queue order"
        case .name: return "Name"
        case .progress: return "Progress"
        case .size: return "Size"
        case .ratio: return "Ratio"
        case .added: return "Date added"
        case .downRate: return "Download speed"
        case .upRate: return "Upload speed"
        }
    }
}
