import SwiftUI

/// Manual release picker, shared by Sonarr and Radarr (`/release` has the same shape in both).
struct InteractiveSearchSheet: View {
    let title: String
    let tint: Color
    let load: () async -> [ArrRelease]
    let grab: (ArrRelease) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var releases: [ArrRelease] = []
    @State private var state: LoadState = .loading
    @State private var hideRejected = true
    @State private var grabbing: String?
    @State private var sort: Sort = .weight

    private enum Sort: String, CaseIterable, Identifiable {
        case weight, size, age
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weight: return "Best match"
            case .size: return "Largest"
            case .age: return "Newest"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Manual search").font(.headline)
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle("Hide rejected", isOn: $hideRejected)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            .hairline()

            if state.isLoading {
                LoadingOverlay(text: "Asking indexers…")
            } else if let error = state.errorMessage {
                ErrorBanner(message: error, retry: { Task { await reload() } }).padding()
                Spacer()
            } else if visible.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: "No releases",
                               message: hideRejected
                                   ? "Every result was rejected by your profile. Untick “Hide rejected” to see them."
                                   : "No indexer returned anything for this item.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visible) { release in
                            ReleaseRow(release: release, tint: tint,
                                       isGrabbing: grabbing == release.id) {
                                grabbing = release.id
                                Task {
                                    await grab(release)
                                    grabbing = nil
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 900, height: 620)
        .task { await reload() }
    }

    private var visible: [ArrRelease] {
        var list = hideRejected ? releases.filter { !($0.rejected ?? false) } : releases
        switch sort {
        case .weight: list.sort { ($0.releaseWeight ?? 0) < ($1.releaseWeight ?? 0) }
        case .size: list.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        case .age: list.sort { ($0.ageHours ?? 1e9) < ($1.ageHours ?? 1e9) }
        }
        return list
    }

    private func reload() async {
        state = .loading
        releases = await load()
        state = .loaded
    }
}

struct ReleaseRow: View {
    let release: ArrRelease
    let tint: Color
    let isGrabbing: Bool
    let onGrab: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(release.title ?? "Untitled")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 5) {
                    Pill(text: release.quality?.name ?? "Unknown", tint: tint)
                    Pill(text: Fmt.bytes(release.size), tint: .secondary)
                    Pill(text: release.indexer ?? "—", tint: .secondary, icon: "antenna.radiowaves.left.and.right")
                    if let age = release.ageHours {
                        Pill(text: age < 24 ? "\(Int(age))h" : "\(Int(age / 24))d",
                             tint: .secondary, icon: "clock")
                    }
                    if release.isUsenet {
                        Pill(text: "Usenet", tint: Theme.nzbget)
                    } else if let seeders = release.seeders {
                        Pill(text: "\(seeders) seeders", tint: Theme.positive)
                    }
                    if let score = release.customFormatScore, score != 0 {
                        Pill(text: "CF \(score)", tint: score > 0 ? Theme.positive : Theme.warning)
                    }
                }
                if let rejections = release.rejections, !rejections.isEmpty {
                    Text(rejections.joined(separator: " · "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                onGrab()
            } label: {
                if isGrabbing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(release.rejected ?? false ? Theme.warning : tint)
            .help(release.rejected ?? false ? "Rejected — grab anyway" : "Send to download client")
            .disabled(isGrabbing)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.05) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder((release.rejected ?? false) ? Theme.danger.opacity(0.25) : Color.primary.opacity(0.06),
                              lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

/// Shared filter/sort/layout controls for the two libraries.
struct LibraryToolbar: View {
    @Binding var filter: ArrMonitorFilter
    @Binding var sortKey: ArrSortKey
    @Binding var ascending: Bool
    @Binding var showList: Bool

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $filter) {
                ForEach(ArrMonitorFilter.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)

            Menu {
                ForEach(ArrSortKey.allCases) { key in
                    Button {
                        sortKey = key
                    } label: {
                        Label(key.label, systemImage: sortKey == key ? "checkmark" : "")
                    }
                }
                Divider()
                Button(ascending ? "Descending" : "Ascending") { ascending.toggle() }
            } label: {
                Label(sortKey.label, systemImage: ascending ? "arrow.up" : "arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Picker("", selection: $showList) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "list.bullet").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}
