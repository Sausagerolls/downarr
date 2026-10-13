import AppKit
import SwiftUI

/// Artwork manager: current images, remote artwork browser, upload and delete.
struct JellyfinImagesSheet: View {
    let item: JellyfinItem

    @EnvironmentObject private var jellyfin: JellyfinStore
    @Environment(\.dismiss) private var dismiss

    @State private var current: [JellyfinImageInfo] = []
    @State private var remote: [JellyfinRemoteImage] = []
    @State private var providers: [String] = []
    @State private var selectedType = "Primary"
    @State private var selectedProvider: String?
    @State private var allLanguages = false
    @State private var loadingCurrent = true
    @State private var loadingRemote = false
    @State private var working: String?
    @State private var reloadToken = UUID()

    private let imageTypes = ["Primary", "Backdrop", "Logo", "Thumb", "Banner", "Art", "Disc"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Images").font(.headline)
                    Text(item.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            .hairline()

            HSplitView {
                currentPane.frame(minWidth: 280, idealWidth: 320)
                remotePane.frame(minWidth: 460)
            }
        }
        .frame(width: 1000, height: 700)
        .task { await loadCurrent() }
    }

    // MARK: Current images

    private var currentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("On the server").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    Task { await loadCurrent() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            if loadingCurrent {
                LoadingOverlay(text: "Reading images…")
            } else if current.isEmpty {
                EmptyStateView(icon: "photo", title: "No images",
                               message: "This item has no artwork yet.")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(current) { image in
                            CurrentImageCard(
                                item: item,
                                image: image,
                                token: reloadToken,
                                isWorking: working == image.id,
                                onUse: {
                                    selectedType = image.ImageType ?? "Primary"
                                    Task { await loadRemote() }
                                },
                                onDelete: {
                                    working = image.id
                                    Task {
                                        _ = await jellyfin.deleteImage(itemID: item.Id,
                                                                       type: image.ImageType ?? "Primary",
                                                                       index: image.ImageIndex)
                                        working = nil
                                        await loadCurrent()
                                    }
                                })
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            HStack {
                Picker("", selection: $selectedType) {
                    ForEach(imageTypes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                Button {
                    uploadFile()
                } label: {
                    Label("Upload…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: Remote artwork

    private var remotePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Browse artwork").font(.system(size: 11, weight: .semibold))
                Picker("", selection: $selectedType) {
                    ForEach(imageTypes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                Picker("", selection: $selectedProvider) {
                    Text("All providers").tag(String?.none)
                    ForEach(providers, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 140)
                Toggle("All languages", isOn: $allLanguages)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button {
                    Task { await loadRemote() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }
            .padding(12)
            .hairline()

            if loadingRemote {
                LoadingOverlay(text: "Fetching artwork…")
            } else if remote.isEmpty {
                EmptyStateView(icon: "photo.on.rectangle.angled",
                               title: "No artwork loaded",
                               message: "Pick an image type and hit Search to see what the providers have.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(remote) { image in
                            RemoteImageCard(image: image,
                                            isWorking: working == image.id,
                                            onApply: { apply(image) })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onChange(of: selectedType) { _, _ in Task { await loadRemote() } }
        .onChange(of: selectedProvider) { _, _ in Task { await loadRemote() } }
        .onChange(of: allLanguages) { _, _ in Task { await loadRemote() } }
    }

    // MARK: Actions

    private func loadCurrent() async {
        loadingCurrent = true
        current = await jellyfin.images(itemID: item.Id)
        reloadToken = UUID()
        loadingCurrent = false
    }

    private func loadRemote() async {
        loadingRemote = true
        let response = await jellyfin.remoteImages(itemID: item.Id,
                                                   type: selectedType,
                                                   provider: selectedProvider,
                                                   allLanguages: allLanguages)
        remote = response?.Images ?? []
        if let list = response?.Providers, !list.isEmpty { providers = list }
        loadingRemote = false
    }

    private func apply(_ image: JellyfinRemoteImage) {
        guard let url = image.Url else { return }
        working = image.id
        Task {
            _ = await jellyfin.applyRemoteImage(itemID: item.Id,
                                                type: image.ImageType ?? selectedType,
                                                url: url)
            working = nil
            await loadCurrent()
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to use as the \(selectedType.lowercased()) artwork"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = "upload"
        Task {
            _ = await jellyfin.uploadImage(itemID: item.Id, type: selectedType, fileURL: url)
            working = nil
            await loadCurrent()
        }
    }
}

private struct CurrentImageCard: View {
    let item: JellyfinItem
    let image: JellyfinImageInfo
    let token: UUID
    let isWorking: Bool
    let onUse: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var jellyfin: JellyfinStore

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: url, contentMode: .fit, systemPlaceholder: "photo")
                .frame(width: 70, height: 100)
                .background(Theme.posterPlaceholder)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(image.ImageType ?? "Image").font(.system(size: 12, weight: .medium))
                Text(image.dimensions).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(Fmt.bytes(image.Size)).font(.system(size: 10)).foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Button("Replace", action: onUse)
                        .controlSize(.small)
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Delete", role: .destructive, action: onDelete)
                            .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10, radius: 9)
    }

    /// The token forces a fresh URL (and therefore a fresh fetch) after artwork changes.
    private var url: URL? {
        guard var comps = jellyfin.imageURL(itemID: item.Id,
                                            type: image.ImageType ?? "Primary",
                                            index: image.ImageIndex,
                                            maxHeight: 220)
            .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "cb", value: token.uuidString))
        comps.queryItems = items
        return comps.url
    }
}

private struct RemoteImageCard: View {
    let image: JellyfinRemoteImage
    let isWorking: Bool
    let onApply: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RemoteImage(url: (image.ThumbnailUrl ?? image.Url).flatMap(URL.init(string:)),
                            contentMode: .fit,
                            systemPlaceholder: "photo")
                    .frame(width: 150, height: 150)
                    .background(Theme.posterPlaceholder)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if hovering || isWorking {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45))
                    if isWorking {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Button("Use this", action: onApply)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.jellyfin)
                            .controlSize(.small)
                    }
                }
            }
            HStack(spacing: 4) {
                if let provider = image.ProviderName {
                    Text(provider).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }
                Spacer()
                if let language = image.Language { Pill(text: language.uppercased(), tint: .secondary) }
            }
            HStack(spacing: 4) {
                Text(image.dimensions).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                if let rating = image.CommunityRating {
                    Text(String(format: "★ %.1f", rating))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.radarr)
                }
                if let votes = image.VoteCount, votes > 0 {
                    Text("(\(votes))").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 150)
        .onHover { hovering = $0 }
    }
}
