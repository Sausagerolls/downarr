import Foundation
import SwiftUI

// NZBGet's JSON-RPC uses PascalCase keys. The model properties mirror those keys exactly rather
// than mapping ~50 of them through CodingKeys, so the structs read like the API documentation.

struct NZBGetStatus: Codable, Hashable {
    var RemainingSizeMB: Int?
    var DownloadedSizeMB: Int?
    var DownloadRate: Int?
    var AverageDownloadRate: Int?
    var DownloadLimit: Int?
    var ThreadCount: Int?
    var ParJobCount: Int?
    var PostJobCount: Int?
    var UrlCount: Int?
    var UpTimeSec: Int?
    var DownloadTimeSec: Int?
    var ServerPaused: Bool?
    var DownloadPaused: Bool?
    var Download2Paused: Bool?
    var ServerStandBy: Bool?
    var PostPaused: Bool?
    var ScanPaused: Bool?
    var QuotaReached: Bool?
    var FreeDiskSpaceMB: Int?
    var ArticleCacheMB: Int?
    var ServerTime: Int?
    var QueueScriptCount: Int?

    var isPaused: Bool { DownloadPaused ?? false }
    var rateBytes: Int { DownloadRate ?? 0 }
}

struct NZBGetGroup: Codable, Hashable, Identifiable {
    var NZBID: Int = 0
    var NZBName: String?
    var NZBNicename: String?
    var Kind: String?
    var Status: String?
    var Category: String?
    var FileSizeMB: Int?
    var RemainingSizeMB: Int?
    var DownloadedSizeMB: Int?
    var PausedSizeMB: Int?
    var FileCount: Int?
    var RemainingFileCount: Int?
    var RemainingParCount: Int?
    var MinPriority: Int?
    var MaxPriority: Int?
    var ActiveDownloads: Int?
    var Health: Int?
    var CriticalHealth: Int?
    var DestDir: String?
    var FinalDir: String?
    var DownloadTimeSec: Int?
    var PostTotalTimeSec: Int?
    var PostStageProgress: Int?
    var PostStageTimeSec: Int?
    var PostStageName: String?
    var DupeKey: String?
    var DupeScore: Int?

    var id: Int { NZBID }
    var name: String { NZBNicename ?? NZBName ?? "Unnamed" }
    var progress: Double {
        guard let total = FileSizeMB, total > 0 else { return 0 }
        let done = total - (RemainingSizeMB ?? 0)
        return max(0, min(1, Double(done) / Double(total)))
    }
    var isPaused: Bool { (Status ?? "").uppercased().contains("PAUSED") }
    var isPostProcessing: Bool {
        let s = (Status ?? "").uppercased()
        return s.contains("PP_") || s.contains("REPAIR") || s.contains("UNPACK") || s.contains("VERIF")
    }
    var healthPercent: Double { Double(Health ?? 1000) / 10.0 }
    var priorityLabel: String { NZBGetPriority.label(for: MaxPriority ?? 0) }
    var statusLabel: String {
        let raw = (Status ?? "").replacingOccurrences(of: "_", with: " ")
        if isPostProcessing, let stage = PostStageName, !stage.isEmpty { return stage }
        return raw.capitalized
    }
    var statusTint: Color {
        let s = (Status ?? "").uppercased()
        if s.contains("PAUSED") { return Theme.warning }
        if s.contains("DOWNLOADING") { return Theme.nzbget }
        if isPostProcessing { return Theme.jellyfin }
        if s.contains("QUEUED") { return Theme.neutral }
        return Theme.neutral
    }
}

struct NZBGetHistoryItem: Codable, Hashable, Identifiable {
    var NZBID: Int = 0
    var Name: String?
    var NZBName: String?
    var NZBNicename: String?
    var Kind: String?
    var Status: String?
    var Category: String?
    var FileSizeMB: Int?
    var DownloadedSizeMB: Int?
    var HistoryTime: Int?
    var DestDir: String?
    var FinalDir: String?
    var DownloadTimeSec: Int?
    var ParStatus: String?
    var UnpackStatus: String?
    var MoveStatus: String?
    var ScriptStatus: String?
    var DeleteStatus: String?
    var MarkStatus: String?
    var Health: Int?
    var FileCount: Int?
    var TotalArticles: Int?
    var FailedArticles: Int?
    var UrlStatus: String?

    var id: Int { NZBID }
    var name: String { NZBNicename ?? Name ?? NZBName ?? "Unnamed" }
    var date: Date? { HistoryTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var succeeded: Bool { (Status ?? "").uppercased().hasPrefix("SUCCESS") }
    var wasDeleted: Bool { (Status ?? "").uppercased().hasPrefix("DELETED") }
    var statusTint: Color {
        if succeeded { return Theme.positive }
        if wasDeleted { return Theme.neutral }
        return Theme.danger
    }
    var failureDetail: String? {
        guard !succeeded else { return nil }
        var bits: [String] = []
        for (label, value) in [("Par", ParStatus), ("Unpack", UnpackStatus),
                               ("Move", MoveStatus), ("Script", ScriptStatus)] {
            if let value, !["NONE", "SUCCESS", "SKIPPED", "OK"].contains(value.uppercased()) {
                bits.append("\(label): \(value)")
            }
        }
        if let failed = FailedArticles, failed > 0 { bits.append("\(failed) failed articles") }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
    var speed: String {
        guard let mb = DownloadedSizeMB, let secs = DownloadTimeSec, secs > 0, mb > 0 else { return "—" }
        return Fmt.rate(Int(Double(mb) * 1_048_576 / Double(secs)))
    }
}

enum NZBGetPriority: Int, CaseIterable, Identifiable {
    case veryLow = -100, low = -50, normal = 0, high = 50, veryHigh = 100, force = 900

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .veryLow: return "Very low"
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .veryHigh: return "Very high"
        case .force: return "Force"
        }
    }

    static func label(for value: Int) -> String {
        if let exact = NZBGetPriority(rawValue: value) { return exact.label }
        return "Priority \(value)"
    }
}

struct NZBGetServerVolume: Codable, Hashable {
    var ServerID: Int?
    var TotalSizeMB: Int?
    var BytesPerDays: [NZBGetVolumeSlot]?
}

struct NZBGetVolumeSlot: Codable, Hashable {
    var SizeMB: Int?
}
