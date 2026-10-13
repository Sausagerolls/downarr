import SwiftUI

// MARK: - Queue

struct NZBGetQueueView: View {
    @EnvironmentObject private var nzbget: NZBGetStore
    @State private var selection: Set<Int> = []
    @State private var showAdd = false

    var body: some View {
        PageScaffold(title: "Download queue",
                     subtitle: subtitle,
                     error: nzbget.state.errorMessage,
                     onRetry: { Task { await nzbget.load(force: true) } }) {
            HStack(spacing: 8) {
                SpeedLimitMenu()
                PauseMenu()
                Button {
                    showAdd = true
                } label: {
                    Label("Add NZB", systemImage: "plus")
                }
                Button {
                    Task { await nzbget.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if nzbget.groups.isEmpty {
                    EmptyStateView(icon: "tray",
                                   title: nzbget.isPaused ? "Queue empty (paused)" : "Queue empty",
                                   message: "Nothing is downloading. Sonarr and Radarr will fill this in when they grab a release.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(nzbget.groups) { group in
                                QueueGroupRow(group: group,
                                              isSelected: selection.contains(group.NZBID),
                                              toggleSelection: {
                                                  if selection.contains(group.NZBID) {
                                                      selection.remove(group.NZBID)
                                                  } else {
                                                      selection.insert(group.NZBID)
                                                  }
                                              })
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty { bulkBar }
        }
        .sheet(isPresented: $showAdd) { NZBGetAddSheet() }
        .task { await nzbget.load() }
    }

    private var subtitle: String {
        if nzbget.groups.isEmpty { return nzbget.isPaused ? "Paused" : "Idle" }
        return "\(nzbget.groups.count) items · \(Fmt.bytes(nzbget.remainingBytes)) remaining · \(Fmt.rate(nzbget.downloadRate)) · ETA \(nzbget.eta)"
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Pause") { act { await nzbget.pauseGroups(Array(selection), paused: true) } }
            Button("Resume") { act { await nzbget.pauseGroups(Array(selection), paused: false) } }
            Menu("Priority") {
                ForEach(NZBGetPriority.allCases) { priority in
                    Button(priority.label) { act { await nzbget.setPriority(Array(selection), priority: priority) } }
                }
            }
            .fixedSize()
            Button("Top") { act { await nzbget.move(Array(selection), to: .top) } }
            Button("Bottom") { act { await nzbget.move(Array(selection), to: .bottom) } }
            Button("Delete", role: .destructive) { act { await nzbget.deleteGroups(Array(selection), deleteFiles: false) } }
            Button("Delete + files", role: .destructive) { act { await nzbget.deleteGroups(Array(selection), deleteFiles: true) } }
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

private struct QueueGroupRow: View {
    let group: NZBGetGroup
    let isSelected: Bool
    let toggleSelection: () -> Void

    @EnvironmentObject private var nzbget: NZBGetStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.nzbget : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .textSelection(.enabled)
                    if group.isPaused { Pill(text: "Paused", tint: Theme.warning) }
                    if group.isPostProcessing { Pill(text: group.statusLabel, tint: Theme.jellyfin) }
                }
                ProgressBarView(value: group.isPostProcessing
                                    ? Double(group.PostStageProgress ?? 0) / 1000.0
                                    : group.progress,
                                tint: group.statusTint, height: 5)
                HStack(spacing: 8) {
                    Text("\(Int(group.progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(group.statusTint)
                    Text("\(Fmt.megabytes(group.DownloadedSizeMB)) of \(Fmt.megabytes(group.FileSizeMB))")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let category = group.Category, !category.isEmpty {
                        Pill(text: category, tint: Theme.nzbget)
                    }
                    Pill(text: group.priorityLabel, tint: .secondary, icon: "arrow.up.arrow.down")
                    if group.healthPercent < 100 {
                        Pill(text: "Health \(Int(group.healthPercent))%",
                             tint: group.healthPercent < 90 ? Theme.danger : Theme.warning)
                    }
                    if (group.ActiveDownloads ?? 0) > 0 {
                        Pill(text: "\(group.ActiveDownloads ?? 0) connections", tint: Theme.nzbget, icon: "bolt.fill")
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 4) {
                Button {
                    Task { await nzbget.pauseGroups([group.NZBID], paused: !group.isPaused) }
                } label: {
                    Image(systemName: group.isPaused ? "play.fill" : "pause.fill").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help(group.isPaused ? "Resume" : "Pause")

                Menu {
                    Button("Move to top") { Task { await nzbget.move([group.NZBID], to: .top) } }
                    Button("Move up") { Task { await nzbget.move([group.NZBID], to: .up) } }
                    Button("Move down") { Task { await nzbget.move([group.NZBID], to: .down) } }
                    Button("Move to bottom") { Task { await nzbget.move([group.NZBID], to: .bottom) } }
                    Divider()
                    Menu("Priority") {
                        ForEach(NZBGetPriority.allCases) { priority in
                            Button(priority.label) {
                                Task { await nzbget.setPriority([group.NZBID], priority: priority) }
                            }
                        }
                    }
                    if !nzbget.categories.isEmpty {
                        Menu("Category") {
                            ForEach(nzbget.categories, id: \.self) { category in
                                Button(category) {
                                    Task { await nzbget.setCategory([group.NZBID], category: category) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Delete") { Task { await nzbget.deleteGroups([group.NZBID], deleteFiles: false) } }
                    Button("Delete with files", role: .destructive) {
                        Task { await nzbget.deleteGroups([group.NZBID], deleteFiles: true) }
                    }
                    if let dir = group.DestDir {
                        Divider()
                        Button("Copy destination path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dir, forType: .string)
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
                .fill(isSelected ? Theme.nzbget.opacity(0.08) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.nzbget.opacity(0.4) : Color.primary.opacity(0.07), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

struct SpeedLimitMenu: View {
    @EnvironmentObject private var nzbget: NZBGetStore

    private let presets: [(String, Int)] = [
        ("Unlimited", 0), ("1 MB/s", 1024), ("5 MB/s", 5120),
        ("10 MB/s", 10240), ("25 MB/s", 25600), ("50 MB/s", 51200),
    ]

    var body: some View {
        Menu {
            ForEach(presets, id: \.1) { preset in
                Button {
                    Task { await nzbget.setSpeedLimit(kilobytesPerSecond: preset.1) }
                } label: {
                    if (nzbget.status?.DownloadLimit ?? 0) / 1024 == preset.1 / 1024 {
                        Label(preset.0, systemImage: "checkmark")
                    } else {
                        Text(preset.0)
                    }
                }
            }
        } label: {
            Label(limitLabel, systemImage: "speedometer")
        }
        .fixedSize()
    }

    private var limitLabel: String {
        let limit = nzbget.status?.DownloadLimit ?? 0
        return limit == 0 ? "Unlimited" : Fmt.rate(limit)
    }
}

// MARK: - Add

struct NZBGetAddSheet: View {
    @EnvironmentObject private var nzbget: NZBGetStore
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var category = ""
    @State private var priority: NZBGetPriority = .normal
    @State private var paused = false
    @State private var addToTop = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add NZB by URL").font(.headline).padding(16)
            Divider()
            Form {
                TextField("NZB URL", text: $url, prompt: Text("https://…"))
                Picker("Category", selection: $category) {
                    Text("None").tag("")
                    ForEach(nzbget.categories, id: \.self) { Text($0).tag($0) }
                }
                Picker("Priority", selection: $priority) {
                    ForEach(NZBGetPriority.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Add paused", isOn: $paused)
                Toggle("Add to top of queue", isOn: $addToTop)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    working = true
                    Task {
                        let ok = await nzbget.addURL(url, category: category, priority: priority,
                                                     paused: paused, addToTop: addToTop)
                        working = false
                        if ok { dismiss() }
                    }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.nzbget)
                .disabled(url.isEmpty || working)
            }
            .padding(16)
        }
        .frame(width: 480)
    }
}

// MARK: - History

struct NZBGetHistoryView: View {
    @EnvironmentObject private var nzbget: NZBGetStore
    @State private var selection: Set<Int> = []

    var body: some View {
        PageScaffold(title: "Download history",
                     subtitle: "\(nzbget.history.count) items · \(nzbget.history.filter(\.succeeded).count) succeeded") {
            Button {
                Task { await nzbget.load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        } content: {
            Group {
                if nzbget.history.isEmpty {
                    EmptyStateView(icon: "tray.full", title: "No history",
                                   message: "NZBGet has not recorded any completed downloads.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(nzbget.filteredHistory) { item in
                                HistoryRow(item: item)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .searchable(text: $nzbget.historySearch, placement: .toolbar, prompt: "Search history")
        .task { await nzbget.load() }
    }
}

private struct HistoryRow: View {
    let item: NZBGetHistoryItem
    @EnvironmentObject private var nzbget: NZBGetStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(item.statusTint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Pill(text: (item.Status ?? "—").replacingOccurrences(of: "/", with: " · "),
                         tint: item.statusTint)
                    if let category = item.Category, !category.isEmpty {
                        Pill(text: category, tint: Theme.nzbget)
                    }
                    Pill(text: Fmt.megabytes(item.FileSizeMB), tint: .secondary)
                    Pill(text: item.speed, tint: .secondary, icon: "speedometer")
                    Pill(text: Fmt.ago(item.date), tint: .secondary, icon: "clock")
                }
                if let detail = item.failureDetail {
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(Theme.danger)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Re-download") { Task { await nzbget.historyAction([item.NZBID], .redownload) } }
                Button("Return to queue") { Task { await nzbget.historyAction([item.NZBID], .returnToQueue) } }
                Divider()
                Button("Mark good") { Task { await nzbget.historyAction([item.NZBID], .markGood) } }
                Button("Mark bad") { Task { await nzbget.historyAction([item.NZBID], .markBad) } }
                Divider()
                Button("Remove from history") { Task { await nzbget.historyAction([item.NZBID], .delete) } }
                Button("Delete with files", role: .destructive) {
                    Task { await nzbget.historyAction([item.NZBID], .deleteFinal) }
                }
                if let dir = item.DestDir {
                    Divider()
                    Button("Copy path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(dir, forType: .string)
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 9))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .opacity(hovering ? 1 : 0.4)
        }
        .padding(10)
        .card(padding: 10, radius: 9)
        .onHover { hovering = $0 }
    }
}

// MARK: - Server

struct NZBGetStatusView: View {
    @EnvironmentObject private var nzbget: NZBGetStore
    @State private var showReloadConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        PageScaffold(title: "NZBGet server",
                     subtitle: nzbget.version.map { "Version \($0)" } ?? nil,
                     error: nzbget.state.errorMessage,
                     onRetry: { Task { await nzbget.load(force: true) } }) {
            HStack(spacing: 8) {
                SpeedLimitMenu()
                Button {
                    Task { await nzbget.scan() }
                } label: {
                    Label("Scan watch folder", systemImage: "folder.badge.gearshape")
                }
                Button {
                    showReloadConfirm = true
                } label: {
                    Label("Reload", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatTile(title: "Download rate",
                                 value: Fmt.rate(nzbget.downloadRate),
                                 subtitle: nzbget.isPaused ? "paused" : "live",
                                 icon: "speedometer",
                                 tint: nzbget.isPaused ? Theme.warning : Theme.nzbget)
                        StatTile(title: "Remaining",
                                 value: Fmt.bytes(nzbget.remainingBytes),
                                 subtitle: "ETA \(nzbget.eta)",
                                 icon: "hourglass", tint: Theme.nzbget)
                        StatTile(title: "Free disk",
                                 value: Fmt.bytes(nzbget.freeDiskBytes),
                                 subtitle: "download volume",
                                 icon: "externaldrive", tint: .accentColor)
                        StatTile(title: "Downloaded",
                                 value: Fmt.megabytes(nzbget.status?.DownloadedSizeMB),
                                 subtitle: "since startup",
                                 icon: "arrow.down.circle", tint: Theme.positive)
                        StatTile(title: "Uptime",
                                 value: Fmt.duration(nzbget.status?.UpTimeSec),
                                 subtitle: "\(nzbget.status?.ThreadCount ?? 0) threads",
                                 icon: "clock.arrow.circlepath", tint: .accentColor)
                        StatTile(title: "Article cache",
                                 value: Fmt.megabytes(nzbget.status?.ArticleCacheMB),
                                 subtitle: "\(nzbget.status?.PostJobCount ?? 0) post jobs",
                                 icon: "memorychip", tint: Theme.jellyfin)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Controls")
                        VStack(spacing: 8) {
                            ForEach(NZBGetStore.PauseTarget.allCases, id: \.self) { target in
                                ControlRow(label: target.label,
                                           isPaused: nzbget.isPaused(target),
                                           isBusy: nzbget.isBusy("pause-\(target)")) {
                                    Task { await nzbget.setPaused(target, !nzbget.isPaused(target)) }
                                }
                                Divider()
                            }
                            HStack {
                                Text("Everything").font(.caption.weight(.semibold))
                                Spacer()
                                Button(nzbget.allPaused ? "Resume all" : "Pause all") {
                                    Task { await nzbget.setAllPaused(!nzbget.allPaused) }
                                }
                                .controlSize(.small)
                                .tint(nzbget.allPaused ? Theme.positive : Theme.warning)
                                .disabled(nzbget.isBusy("pause-all"))
                            }
                        }
                        .card()
                    }

                    if !nzbget.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Categories",
                                          subtitle: "Configured in NZBGet")
                            FlowTags(tags: nzbget.categories, tint: Theme.nzbget)
                                .card()
                        }
                    }
                }
                .padding(18)
            }
        }
        .alert("Reload NZBGet?", isPresented: $showReloadConfirm) {
            Button("Reload", role: .destructive) { Task { await nzbget.reload() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("NZBGet will restart its configuration. Active downloads are paused briefly.")
        }
        .task { await nzbget.load() }
    }
}

private struct ControlRow: View {
    let label: String
    let isPaused: Bool
    var isBusy = false
    let toggle: () -> Void

    var body: some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(isPaused ? "Paused" : "Running")
                .font(.caption)
                .foregroundStyle(isPaused ? Theme.warning : Theme.positive)
            Button(isPaused ? "Resume" : "Pause", action: toggle)
                .controlSize(.small)
                .tint(isPaused ? Theme.positive : Theme.warning)
                .disabled(isBusy)
        }
    }
}

/// Primary click toggles downloads; the menu exposes post-processing, scanning and "all".
struct PauseMenu: View {
    @EnvironmentObject private var nzbget: NZBGetStore

    var body: some View {
        Menu {
            ForEach(NZBGetStore.PauseTarget.allCases, id: \.self) { target in
                let paused = nzbget.isPaused(target)
                Button {
                    Task { await nzbget.setPaused(target, !paused) }
                } label: {
                    Label("\(paused ? "Resume" : "Pause") \(target.label.lowercased())",
                          systemImage: paused ? "play.fill" : "pause.fill")
                }
            }
            Divider()
            Button {
                Task { await nzbget.setAllPaused(!nzbget.allPaused) }
            } label: {
                Label(nzbget.allPaused ? "Resume all" : "Pause all",
                      systemImage: nzbget.allPaused ? "play.circle" : "pause.circle")
            }
        } label: {
            Label(nzbget.isPaused ? "Resume" : "Pause",
                  systemImage: nzbget.isPaused ? "play.fill" : "pause.fill")
        } primaryAction: {
            Task { await nzbget.togglePause() }
        }
        .tint(nzbget.isPaused ? Theme.positive : Theme.warning)
        .fixedSize()
        .help("Click to toggle downloads; open the menu for post-processing and scanning")
    }
}
