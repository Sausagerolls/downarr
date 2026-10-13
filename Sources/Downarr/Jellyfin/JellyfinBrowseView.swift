import SwiftUI

struct JellyfinBrowseView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var searchDebounce: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        PageScaffold(title: "Browse Jellyfin",
                     subtitle: subtitle,
                     error: jellyfin.browseState.errorMessage,
                     onRetry: { Task { await jellyfin.loadItems() } }) {
            HStack(spacing: 8) {
                Picker("", selection: $jellyfin.selectedLibraryID) {
                    Text("All libraries").tag(String?.none)
                    ForEach(jellyfin.libraries) { folder in
                        Text(folder.Name ?? "Library").tag(folder.ItemId)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Picker("", selection: $jellyfin.typeFilter) {
                    ForEach(JellyfinBrowseType.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)

                Menu {
                    ForEach(JellyfinSortOption.allCases) { option in
                        Button {
                            jellyfin.sortBy = option
                        } label: {
                            Label(option.label, systemImage: jellyfin.sortBy == option ? "checkmark" : "")
                        }
                    }
                    Divider()
                    Button(jellyfin.sortAscending ? "Descending" : "Ascending") {
                        jellyfin.sortAscending.toggle()
                    }
                } label: {
                    Label(jellyfin.sortBy.label, systemImage: jellyfin.sortAscending ? "arrow.up" : "arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    Task { await jellyfin.loadItems() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        } content: {
            Group {
                if jellyfin.browseState.isLoading && jellyfin.items.isEmpty {
                    LoadingOverlay(text: "Loading items…")
                } else if jellyfin.items.isEmpty {
                    EmptyStateView(icon: "square.grid.3x3",
                                   title: "Nothing to show",
                                   message: jellyfin.searchText.isEmpty
                                       ? "Pick a library, or change the type filter."
                                       : "No items match “\(jellyfin.searchText)”.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(jellyfin.items) { item in
                                NavigationLink(value: item) {
                                    PosterCard(title: item.Name ?? "Untitled",
                                               subtitle: subtitle(for: item),
                                               imageURL: jellyfin.posterURL(item),
                                               width: 140,
                                               badge: item.isLocked ? "Locked" : nil,
                                               badgeTint: Theme.warning,
                                               placeholderIcon: item.kind.icon)
                                }
                                .buttonStyle(.plain)
                                .onAppear { jellyfin.loadMoreIfNeeded(currentItem: item) }
                                .contextMenu {
                                    Button("Refresh metadata") {
                                        Task {
                                            _ = await jellyfin.refreshItem(id: item.Id, metadata: .standard,
                                                                           images: .standard,
                                                                           replaceMetadata: false,
                                                                           replaceImages: false, recursive: false)
                                        }
                                    }
                                    Button("Replace all metadata") {
                                        Task {
                                            _ = await jellyfin.refreshItem(id: item.Id, metadata: .full,
                                                                           images: .full,
                                                                           replaceMetadata: true,
                                                                           replaceImages: true, recursive: false)
                                        }
                                    }
                                    if let path = item.Path {
                                        Divider()
                                        Button("Copy path") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(path, forType: .string)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        if jellyfin.items.count < jellyfin.totalItems {
                            ProgressView().padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .searchable(text: $jellyfin.searchText, placement: .toolbar, prompt: "Search Jellyfin")
        .navigationDestination(for: JellyfinItem.self) { item in
            JellyfinItemDetailView(itemID: item.Id)
        }
        .task {
            await jellyfin.loadOverview()
            // "All libraries" mixes films, episodes and albums; start somewhere useful instead.
            if jellyfin.selectedLibraryID == nil {
                jellyfin.selectedLibraryID = jellyfin.libraries
                    .first { $0.CollectionType == "movies" }?.ItemId
                    ?? jellyfin.libraries.first?.ItemId
            }
            if jellyfin.items.isEmpty { await jellyfin.loadItems() }
        }
        .onChange(of: jellyfin.selectedLibraryID) { _, _ in Task { await jellyfin.loadItems() } }
        .onChange(of: jellyfin.typeFilter) { _, _ in Task { await jellyfin.loadItems() } }
        .onChange(of: jellyfin.sortBy) { _, _ in Task { await jellyfin.loadItems() } }
        .onChange(of: jellyfin.sortAscending) { _, _ in Task { await jellyfin.loadItems() } }
        .onChange(of: jellyfin.searchText) { _, _ in
            // Debounce so typing doesn't fire a query per keystroke across 60k items.
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await jellyfin.loadItems()
            }
        }
    }

    private var subtitle: String {
        let library = jellyfin.selectedLibrary?.Name ?? "All libraries"
        return "\(library) · showing \(jellyfin.items.count) of \(jellyfin.totalItems.formatted())"
    }

    private func subtitle(for item: JellyfinItem) -> String? {
        switch item.kind {
        case .episode:
            let code = String(format: "S%02dE%02d", item.ParentIndexNumber ?? 0, item.IndexNumber ?? 0)
            return "\(item.SeriesName ?? "") \(code)"
        case .series:
            return [item.ProductionYear.map(String.init), item.ChildCount.map { "\($0) seasons" }]
                .compactMap { $0 }.joined(separator: " · ")
        default:
            return item.ProductionYear.map(String.init)
        }
    }
}
