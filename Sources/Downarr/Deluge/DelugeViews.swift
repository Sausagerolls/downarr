import SwiftUI

// MARK: - Torrents

struct DelugeTorrentsView: View {
    @EnvironmentObject private var deluge: DelugeStore
    @State private var selection: Set<String> = []
    @State private var showAdd = false

    var body: some View {
        PageScaffold(title: "Torrents",
                     subtitle: subtitle,
                     error: deluge.state.errorMessage,
                     onRetry: { Task { await deluge.load(force: true) } }) {
            HStack(spacing: 8) {
                Picker("", selection: $deluge.stateFilter) {
                    ForEach(stateOptions) { option in
                        Text(option.count > 0 ? "\(option.name) (\(option.count))" : option.name)
                            .tag(option.name)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                if deluge.hasLabelPlugin && !deluge.labelCounts.isEmpty {
                    Picker("", selection: $deluge.labelFilter) {
                        Text("Any label").tag(String?.none)
                        ForEach(deluge.labelCounts) { entry in
                            Text(entry.name.isEmpty ? "No label" : entry.name)
                                .tag(String?.some(entry.name))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                Menu {
                    ForEach(DelugeSortKey.allCases) { key in
                        Button {
                            deluge.sortKey = key
                        } label: {
                            Label(key.label, systemImage: deluge.sortKey == key ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button(deluge.sortAscending ? "Descending" : "Ascending") {
                        deluge.sortAscending.toggle()
                    }
                } label: {
                    Label(deluge.sortKey.label, systemImage: deluge.sortAscending ? "arrow.up" : "arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                DelugeSpeedMenu()

                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Button {
                    Task { await deluge.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if deluge.state.isLoading && deluge.torrents.isEmpty {
                    LoadingOverlay(text: "Loading torrents…")
                } else if deluge.torrents.isEmpty {
                    EmptyStateView(icon: "water.waves",
                                   title: "No torrents",
                                   message: "Deluge has nothing in its session. Radarr adds torrents here when it grabs one.",
                                   actionLabel: "Add a magnet") { showAdd = true }
                } else if deluge.filteredTorrents.isEmpty {
                    EmptyStateView(icon: "line.3.horizontal.decrease.circle",
                                   title: "Nothing matches",
                                   message: "No torrent matches the current filters.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(deluge.filteredTorrents) { torrent in
                                TorrentRow(torrent: torrent,
                                           isSelected: selection.contains(torrent.hash),
                                           toggleSelection: {
                                               if selection.contains(torrent.hash) {
                                                   selection.remove(torrent.hash)
                                               } else {
                                                   selection.insert(torrent.hash)
                                               }
                                           })
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .searchable(text: $deluge.searchText, placement: .toolbar, prompt: "Search torrents")
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty { bulkBar }
        }
        .sheet(isPresented: $showAdd) { DelugeAddSheet() }
        .task { await deluge.load() }
    }

    private var stateOptions: [DelugeFilterCount] {
        let counts = deluge.stateCounts
        return counts.isEmpty ? [DelugeFilterCount(name: "All", count: deluge.torrents.count)] : counts
    }

    private var subtitle: String {
        var parts = ["\(deluge.filteredTorrents.count) of \(deluge.torrents.count)"]
        parts.append("↓ \(Fmt.rate(deluge.downloadRate))")
        parts.append("↑ \(Fmt.rate(deluge.uploadRate))")
        if deluge.remainingBytes > 0 { parts.append("\(Fmt.bytes(deluge.remainingBytes)) left · ETA \(deluge.eta)") }
        parts.append("\(Fmt.bytes(deluge.freeSpace)) free")
        return parts.joined(separator: " · ")
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Pause") { act { await deluge.setPaused(Array(selection), paused: true) } }
            Button("Resume") { act { await deluge.setPaused(Array(selection), paused: false) } }
            Button("Top") { act { await deluge.queueMove(Array(selection), .top) } }
            Button("Bottom") { act { await deluge.queueMove(Array(selection), .bottom) } }
            Button("Recheck") { act { await deluge.forceRecheck(Array(selection)) } }
            Button("Remove", role: .destructive) { act { await deluge.remove(Array(selection), deleteData: false) } }
            Button("Remove + data", role: .destructive) { act { await deluge.remove(Array(selection), deleteData: true) } }
            Button("Clear") { selection = [] }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func act(_ work: @escaping () async -> Void) {
        Task {
            await work()
            selection = []
        }
    }
}

private struct TorrentRow: View {
    let torrent: DelugeTorrent
    let isSelected: Bool
    let toggleSelection: () -> Void

    @EnvironmentObject private var deluge: DelugeStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.deluge : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: torrent.statusIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(torrent.statusTint)
                    Text(torrent.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    if let label = torrent.label, !label.isEmpty {
                        Pill(text: label, tint: Theme.deluge)
                    }
                }

                ProgressBarView(value: torrent.fraction, tint: torrent.statusTint, height: 5)

                HStack(spacing: 8) {
                    Text(String(format: "%.1f%%", torrent.progress ?? 0))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(torrent.statusTint)
                    Text("\(Fmt.bytes(torrent.total_done)) of \(Fmt.bytes(torrent.total_wanted))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    Pill(text: torrent.state ?? "—", tint: torrent.statusTint)
                    if (torrent.download_payload_rate ?? 0) > 0 {
                        Pill(text: "↓ \(Fmt.rate(torrent.download_payload_rate))", tint: Theme.deluge)
                    }
                    if (torrent.upload_payload_rate ?? 0) > 0 {
                        Pill(text: "↑ \(Fmt.rate(torrent.upload_payload_rate))", tint: Theme.positive)
                    }
                    Pill(text: String(format: "ratio %.2f", torrent.ratio ?? 0),
                         tint: (torrent.ratio ?? 0) >= 1 ? Theme.positive : .secondary)
                    if !torrent.etaText.isEmpty && torrent.etaText != "—" && !(torrent.is_finished ?? false) {
                        Pill(text: torrent.etaText, tint: .secondary, icon: "hourglass")
                    }
                    Pill(text: torrent.seedsPeers, tint: .secondary, icon: "person.2.fill")
                    if let tracker = torrent.tracker_host, !tracker.isEmpty {
                        Pill(text: tracker, tint: .secondary, icon: "antenna.radiowaves.left.and.right")
                    }
                    Spacer(minLength: 0)
                }

                if let problem = torrent.problem {
                    Text(problem)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 4) {
                Button {
                    Task { await deluge.setPaused([torrent.hash], paused: !torrent.isPaused) }
                } label: {
                    Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help(torrent.isPaused ? "Resume" : "Pause")

                Menu {
                    Button("Move to top") { Task { await deluge.queueMove([torrent.hash], .top) } }
                    Button("Move up") { Task { await deluge.queueMove([torrent.hash], .up) } }
                    Button("Move down") { Task { await deluge.queueMove([torrent.hash], .down) } }
                    Button("Move to bottom") { Task { await deluge.queueMove([torrent.hash], .bottom) } }
                    Divider()
                    Button("Force recheck") { Task { await deluge.forceRecheck([torrent.hash]) } }
                    Menu("Speed limit") {
                        Button("Unlimited") { Task { await deluge.setTorrentSpeedLimit([torrent.hash], downloadKiB: -1) } }
                        ForEach([512.0, 1024.0, 5120.0, 10240.0], id: \.self) { limit in
                            Button("\(Int(limit / 1024)) MiB/s") {
                                Task { await deluge.setTorrentSpeedLimit([torrent.hash], downloadKiB: limit) }
                            }
                        }
                    }
                    if deluge.hasLabelPlugin {
                        Menu("Label") {
                            Button("No label") { Task { await deluge.setLabel(torrent.hash, label: "") } }
                            ForEach(deluge.labels, id: \.self) { label in
                                Button(label) { Task { await deluge.setLabel(torrent.hash, label: label) } }
                            }
                        }
                    }
                    Divider()
                    Button("Remove torrent") { Task { await deluge.remove([torrent.hash], deleteData: false) } }
                    Button("Remove and delete data", role: .destructive) {
                        Task { await deluge.remove([torrent.hash], deleteData: true) }
                    }
                    Divider()
                    Button("Copy info hash") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(torrent.hash, forType: .string)
                    }
                    if let path = torrent.save_path {
                        Button("Copy save path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 9))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .opacity(hovering ? 1 : 0.45)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Theme.deluge.opacity(0.08) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.deluge.opacity(0.4)
                              : (torrent.isError ? Theme.danger.opacity(0.3) : Color.primary.opacity(0.07)),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Speed menu

struct DelugeSpeedMenu: View {
    @EnvironmentObject private var deluge: DelugeStore

    /// Deluge speed caps are KiB/s.
    private let presets: [(String, Double)] = [
        ("Unlimited", -1), ("500 KiB/s", 512), ("1 MiB/s", 1024),
        ("5 MiB/s", 5120), ("10 MiB/s", 10240), ("25 MiB/s", 25600),
    ]

    var body: some View {
        Menu {
            Section("Download limit") {
                ForEach(presets, id: \.1) { preset in
                    Button {
                        Task { await deluge.setSpeedLimits(download: preset.1, upload: nil) }
                    } label: {
                        if isCurrent(deluge.stats?.downloadLimitKiB, preset.1) {
                            Label(preset.0, systemImage: "checkmark")
                        } else {
                            Text(preset.0)
                        }
                    }
                }
            }
            Section("Upload limit") {
                ForEach(presets, id: \.1) { preset in
                    Button {
                        Task { await deluge.setSpeedLimits(download: nil, upload: preset.1) }
                    } label: {
                        if isCurrent(deluge.stats?.uploadLimitKiB, preset.1) {
                            Label(preset.0, systemImage: "checkmark")
                        } else {
                            Text(preset.0)
                        }
                    }
                }
            }
        } label: {
            Label(limitLabel, systemImage: "speedometer")
        }
        .fixedSize()
    }

    private func isCurrent(_ value: Double?, _ preset: Double) -> Bool {
        guard let value else { return false }
        if preset < 0 { return value < 0 }
        return abs(value - preset) < 1
    }

    private var limitLabel: String {
        let down = deluge.stats?.downloadLimitKiB ?? -1
        return down < 0 ? "Unlimited" : "\(Int(down)) KiB/s"
    }
}

// MARK: - Add

struct DelugeAddSheet: View {
    @EnvironmentObject private var deluge: DelugeStore
    @Environment(\.dismiss) private var dismiss

    @State private var uri = ""
    @State private var label = ""
    @State private var paused = false
    @State private var location = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add torrent").font(.headline).padding(16)
            Divider()
            Form {
                TextField("Magnet link or .torrent URL", text: $uri, prompt: Text("magnet:?xt=urn:btih:…"))
                if deluge.hasLabelPlugin {
                    Picker("Label", selection: $label) {
                        Text("None").tag("")
                        ForEach(deluge.labels, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField("Download location", text: $location,
                          prompt: Text(deluge.config["download_location"]?.stringValue ?? "Deluge default"))
                    .font(.system(size: 11, design: .monospaced))
                Toggle("Add paused", isOn: $paused)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Paste from clipboard") {
                    if let clip = NSPasteboard.general.string(forType: .string) { uri = clip }
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    working = true
                    Task {
                        let ok = await deluge.add(uri, label: label, paused: paused,
                                                  downloadLocation: location)
                        working = false
                        if ok { dismiss() }
                    }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.deluge)
                .disabled(uri.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            .padding(16)
        }
        .frame(width: 520)
    }
}

// MARK: - Server

struct DelugeServerView: View {
    @EnvironmentObject private var deluge: DelugeStore

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        PageScaffold(title: "Deluge server",
                     subtitle: deluge.version.map { "Version \($0)" },
                     error: deluge.state.errorMessage,
                     onRetry: { Task { await deluge.load(force: true) } }) {
            HStack(spacing: 8) {
                DelugeSpeedMenu()
                Button {
                    Task { await deluge.setSessionPaused(!deluge.isAllPaused) }
                } label: {
                    Label(deluge.isAllPaused ? "Resume all" : "Pause all",
                          systemImage: deluge.isAllPaused ? "play.fill" : "pause.fill")
                }
                Button {
                    Task { await deluge.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatTile(title: "Download", value: Fmt.rate(deluge.downloadRate),
                                 subtitle: "\(deluge.downloadingCount) downloading",
                                 icon: "arrow.down.circle", tint: Theme.deluge)
                        StatTile(title: "Upload", value: Fmt.rate(deluge.uploadRate),
                                 subtitle: "\(deluge.seedingCount) seeding",
                                 icon: "arrow.up.circle", tint: Theme.positive)
                        StatTile(title: "Remaining", value: Fmt.bytes(deluge.remainingBytes),
                                 subtitle: "ETA \(deluge.eta)",
                                 icon: "hourglass", tint: Theme.deluge)
                        StatTile(title: "Free space", value: Fmt.bytes(deluge.freeSpace),
                                 subtitle: deluge.config["download_location"]?.stringValue,
                                 icon: "externaldrive", tint: .accentColor)
                        StatTile(title: "Connections",
                                 value: "\(deluge.stats?.num_connections ?? 0)",
                                 subtitle: "max \(deluge.stats?.max_num_connections ?? 0)",
                                 icon: "point.3.connected.trianglepath.dotted", tint: .accentColor)
                        StatTile(title: "DHT nodes",
                                 value: (deluge.stats?.dht_nodes ?? 0).formatted(),
                                 subtitle: (deluge.stats?.acceptsIncoming ?? false)
                                     ? "accepting incoming" : "no incoming connections",
                                 icon: "network",
                                 tint: (deluge.stats?.acceptsIncoming ?? false) ? Theme.positive : Theme.warning)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Session",
                                      subtitle: "\(deluge.torrents.count) torrents · \(deluge.pausedCount) paused · \(deluge.errorCount) errored")
                        VStack(alignment: .leading, spacing: 6) {
                            KeyValueRow(key: "Download location",
                                        value: deluge.config["download_location"]?.stringValue ?? "—")
                            KeyValueRow(key: "Completed path",
                                        value: deluge.config["move_completed_path"]?.stringValue ?? "—")
                            KeyValueRow(key: "Download limit", value: limitText(deluge.stats?.downloadLimitKiB))
                            KeyValueRow(key: "Upload limit", value: limitText(deluge.stats?.uploadLimitKiB))
                            KeyValueRow(key: "Active downloads allowed",
                                        value: deluge.config["max_active_downloading"]?.intValue.map(String.init) ?? "—")
                            KeyValueRow(key: "External IP", value: deluge.stats?.external_ip ?? "—")
                        }
                        .card()
                    }

                    if deluge.hasLabelPlugin {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Labels", subtitle: "From the Label plugin")
                            if deluge.labelCounts.isEmpty {
                                Text("No labels defined.").font(.caption).foregroundStyle(.secondary).card()
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(deluge.labelCounts) { entry in
                                        HStack {
                                            Pill(text: entry.name.isEmpty ? "No label" : entry.name,
                                                 tint: Theme.deluge)
                                            Spacer()
                                            Text("\(entry.count)")
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 6)
                                        if entry.id != deluge.labelCounts.last?.id { Divider() }
                                    }
                                }
                                .card()
                            }
                        }
                    }

                    if !deluge.trackerCounts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Trackers")
                            FlowTags(tags: deluge.trackerCounts.map { "\($0.name) (\($0.count))" },
                                     tint: .secondary)
                                .card()
                        }
                    }
                }
                .padding(18)
            }
        }
        .task { await deluge.load() }
    }

    private func limitText(_ kib: Double?) -> String {
        guard let kib else { return "—" }
        return kib < 0 ? "Unlimited" : "\(Int(kib)) KiB/s"
    }
}
