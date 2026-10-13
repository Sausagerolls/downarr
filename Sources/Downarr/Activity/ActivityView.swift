import SwiftUI

/// One table for everything in flight: the Sonarr and Radarr queues joined to the NZBGet group
/// that is actually moving the bytes, so a stuck import is visible in one place.
struct ActivityView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var sonarr: SonarrStore
    @EnvironmentObject private var radarr: RadarrStore
    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore

    @State private var showProblemsOnly = false

    var body: some View {
        PageScaffold(title: "Activity", subtitle: subtitle) {
            HStack(spacing: 8) {
                Toggle("Problems only", isOn: $showProblemsOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if rows.isEmpty {
                    EmptyStateView(icon: showProblemsOnly ? "checkmark.seal" : "moon.zzz",
                                   title: showProblemsOnly ? "No problems" : "Nothing in flight",
                                   message: showProblemsOnly
                                       ? "Every queued item is importing cleanly."
                                       : "Sonarr and Radarr have empty queues and NZBGet is idle.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(rows) { row in
                                ActivityRow(row: row)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .task { await reload() }
    }

    private var subtitle: String {
        let stuck = rows.filter { $0.problem != nil }.count
        var parts = ["\(rows.count) items"]
        if stuck > 0 { parts.append("\(stuck) need attention") }
        parts.append(nzbget.isPaused ? "NZBGet paused" : Fmt.rate(nzbget.downloadRate))
        return parts.joined(separator: " · ")
    }

    private var rows: [ActivityItem] {
        var result: [ActivityItem] = []

        for record in sonarr.queue {
            result.append(ActivityItem(
                id: "sonarr-\(record.id)",
                source: "Sonarr",
                tint: Theme.sonarr,
                title: record.label,
                detail: record.title ?? "",
                quality: record.quality?.name,
                progress: record.progress,
                size: Int64(record.size ?? 0),
                remaining: Int64(record.sizeleft ?? 0),
                timeLeft: Fmt.timespan(record.timeleft),
                state: record.trackedDownloadState ?? record.status,
                problem: record.problem,
                client: record.downloadClient,
                indexer: record.indexer,
                group: matchGroup(record.title),
                torrent: matchTorrent(record.downloadId, record.title),
                removeAction: { blocklist in
                    await sonarr.removeFromQueue(id: record.id, removeFromClient: true, blocklist: blocklist)
                }))
        }

        for record in radarr.queue {
            result.append(ActivityItem(
                id: "radarr-\(record.id)",
                source: "Radarr",
                tint: Theme.radarr,
                title: record.label,
                detail: record.title ?? "",
                quality: record.quality?.name,
                progress: record.progress,
                size: Int64(record.size ?? 0),
                remaining: Int64(record.sizeleft ?? 0),
                timeLeft: Fmt.timespan(record.timeleft),
                state: record.trackedDownloadState ?? record.status,
                problem: record.problem,
                client: record.downloadClient,
                indexer: record.indexer,
                group: matchGroup(record.title),
                torrent: matchTorrent(record.downloadId, record.title),
                removeAction: { blocklist in
                    await radarr.removeFromQueue(id: record.id, removeFromClient: true, blocklist: blocklist)
                }))
        }

        // NZBGet items that no *arr claims (manual adds).
        let claimed = Set(result.compactMap { $0.group?.NZBID })
        for group in nzbget.groups where !claimed.contains(group.NZBID) {
            result.append(ActivityItem(
                id: "nzbget-\(group.NZBID)",
                source: "NZBGet",
                tint: Theme.nzbget,
                title: group.name,
                detail: group.DestDir ?? "",
                quality: group.Category,
                progress: group.progress,
                size: Int64(group.FileSizeMB ?? 0) * 1_048_576,
                remaining: Int64(group.RemainingSizeMB ?? 0) * 1_048_576,
                timeLeft: "—",
                state: group.statusLabel,
                problem: nil,
                client: "NZBGet",
                indexer: nil,
                group: group,
                torrent: nil,
                removeAction: { _ in
                    await nzbget.deleteGroups([group.NZBID], deleteFiles: false)
                }))
        }

        // Torrents no *arr claims (manual adds, or seeding after an import).
        let claimedHashes = Set(result.compactMap { $0.torrent?.hash.lowercased() })
        for torrent in deluge.torrents where !claimedHashes.contains(torrent.hash.lowercased()) {
            guard torrent.isDownloading || torrent.isError || torrent.isActive else { continue }
            result.append(ActivityItem(
                id: "deluge-\(torrent.hash)",
                source: "Deluge",
                tint: Theme.deluge,
                title: torrent.title,
                detail: torrent.save_path ?? "",
                quality: torrent.label?.isEmpty == false ? torrent.label : nil,
                progress: torrent.fraction,
                size: torrent.total_wanted ?? torrent.total_size ?? 0,
                remaining: torrent.remaining,
                timeLeft: torrent.etaText,
                state: torrent.state,
                problem: torrent.problem,
                client: "Deluge",
                indexer: torrent.tracker_host,
                group: nil,
                torrent: torrent,
                removeAction: { _ in
                    await deluge.remove([torrent.hash], deleteData: false)
                }))
        }

        result.sort { ($0.problem != nil ? 0 : 1, -$0.progress) < ($1.problem != nil ? 0 : 1, -$1.progress) }
        return showProblemsOnly ? result.filter { $0.problem != nil } : result
    }

    /// The *arrs report a download client id that NZBGet does not echo back, so match on the
    /// release name instead — it is the same string on both sides.
    private func matchGroup(_ title: String?) -> NZBGetGroup? {
        guard let title else { return nil }
        let needle = normalize(title)
        return nzbget.groups.first { normalize($0.name) == needle }
            ?? nzbget.groups.first { normalize($0.name).hasPrefix(needle.prefix(40)) }
    }

    /// The *arrs report a torrent's infohash as its download id, which Deluge keys torrents by —
    /// an exact join. Fall back to the release name for anything that does not line up.
    private func matchTorrent(_ downloadID: String?, _ title: String?) -> DelugeTorrent? {
        if let downloadID, !downloadID.isEmpty, let hit = deluge.torrent(hash: downloadID) { return hit }
        guard let title else { return nil }
        let needle = normalize(title)
        return deluge.torrents.first { normalize($0.title) == needle }
    }

    private func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func reload() async {
        async let s: Void = sonarr.loadQueue()
        async let r: Void = radarr.loadQueue()
        async let n: Void = nzbget.load(force: true)
        async let d: Void = deluge.load(force: true)
        _ = await (s, r, n, d)
    }
}

struct ActivityItem: Identifiable {
    let id: String
    let source: String
    let tint: Color
    let title: String
    let detail: String
    let quality: String?
    let progress: Double
    let size: Int64
    let remaining: Int64
    let timeLeft: String
    let state: String?
    let problem: String?
    let client: String?
    let indexer: String?
    let group: NZBGetGroup?
    let torrent: DelugeTorrent?
    let removeAction: (Bool) async -> Void
}

private struct ActivityRow: View {
    let row: ActivityItem

    @EnvironmentObject private var nzbget: NZBGetStore
    @EnvironmentObject private var deluge: DelugeStore
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Pill(text: row.source, tint: row.tint, filled: true)
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let quality = row.quality, !quality.isEmpty {
                    Pill(text: quality, tint: .secondary)
                }
                Spacer(minLength: 0)
                if let state = row.state {
                    Pill(text: state.replacingOccurrences(of: "import", with: "import ").capitalized,
                         tint: arrTrackedStateColor(state))
                }
            }

            ProgressBarView(value: row.progress,
                            tint: row.problem != nil ? Theme.danger : row.tint,
                            height: 5)

            HStack(spacing: 8) {
                Text("\(Int(row.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(row.tint)
                Text("\(Fmt.bytes(row.size - row.remaining)) of \(Fmt.bytes(row.size))")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                if row.timeLeft != "—" {
                    Pill(text: row.timeLeft, tint: .secondary, icon: "hourglass")
                }
                if let indexer = row.indexer, !indexer.isEmpty {
                    Pill(text: indexer, tint: .secondary, icon: "antenna.radiowaves.left.and.right")
                }
                if let group = row.group {
                    Pill(text: group.statusLabel, tint: group.statusTint, icon: "arrow.down.circle")
                    if group.healthPercent < 100 {
                        Pill(text: "Health \(Int(group.healthPercent))%", tint: Theme.warning)
                    }
                } else if let torrent = row.torrent {
                    Pill(text: torrent.state ?? "—", tint: torrent.statusTint, icon: "water.waves")
                    Pill(text: String(format: "ratio %.2f", torrent.ratio ?? 0),
                         tint: (torrent.ratio ?? 0) >= 1 ? Theme.positive : .secondary)
                    if (torrent.upload_payload_rate ?? 0) > 0 {
                        Pill(text: "↑ \(Fmt.rate(torrent.upload_payload_rate))", tint: Theme.positive)
                    }
                } else if row.source != "NZBGet" && row.source != "Deluge" {
                    Pill(text: "Not in a download client", tint: Theme.warning, icon: "questionmark")
                }
                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if let group = row.group {
                        Button {
                            Task { await nzbget.pauseGroups([group.NZBID], paused: !group.isPaused) }
                        } label: {
                            Image(systemName: group.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                        .help(group.isPaused ? "Resume in NZBGet" : "Pause in NZBGet")
                    } else if let torrent = row.torrent {
                        Button {
                            Task { await deluge.setPaused([torrent.hash], paused: !torrent.isPaused) }
                        } label: {
                            Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                        .help(torrent.isPaused ? "Resume in Deluge" : "Pause in Deluge")
                    }
                    Menu {
                        Button("Remove from queue") { Task { await row.removeAction(false) } }
                        Button("Remove and blocklist release", role: .destructive) {
                            Task { await row.removeAction(true) }
                        }
                        if let group = row.group {
                            Divider()
                            Button("Move to top of NZBGet queue") {
                                Task { await nzbget.move([group.NZBID], to: .top) }
                            }
                        }
                        if let torrent = row.torrent {
                            Divider()
                            Button("Move to top of Deluge queue") {
                                Task { await deluge.queueMove([torrent.hash], .top) }
                            }
                            Button("Force recheck") {
                                Task { await deluge.forceRecheck([torrent.hash]) }
                            }
                            Button("Remove torrent and data", role: .destructive) {
                                Task { await deluge.remove([torrent.hash], deleteData: true) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 9))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .opacity(hovering ? 1 : 0.4)
            }

            if let problem = row.problem {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.danger)
                        Text(problem)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.danger)
                            .lineLimit(expanded ? nil : 1)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            if expanded && !row.detail.isEmpty {
                Text(row.detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(row.problem != nil ? Theme.danger.opacity(0.3) : Color.primary.opacity(0.07),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}
