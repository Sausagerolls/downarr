import AppKit
import SwiftUI

/// Memory + disk image cache with in-flight de-duplication.
///
/// `AsyncImage` re-fetches on every scroll recycle, which is unusable across a 689-poster grid,
/// so posters go through here instead.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        c.totalCostLimit = 320 * 1024 * 1024
        return c
    }()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let diskDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDir = base.appendingPathComponent("Downarr/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    private func diskKey(_ url: URL) -> String {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 { hash = (hash << 5) &+ hash &+ UInt64(byte) }
        return String(hash, radix: 36) + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension)
    }

    func cached(_ url: URL) -> NSImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async -> NSImage? {
        let key = url.absoluteString
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<NSImage?, Never> { [diskDir] in
            let file = diskDir.appendingPathComponent(self.diskKeyNonIsolated(url))
            if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
                return image
            }
            guard let (data, response) = try? await HTTPClient.session.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data)
            else { return nil }
            try? data.write(to: file, options: .atomic)
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            memory.setObject(result, forKey: key as NSString, cost: Int(result.size.width * result.size.height * 4))
        }
        return result
    }

    nonisolated private func diskKeyNonIsolated(_ url: URL) -> String {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 { hash = (hash << 5) &+ hash &+ UInt64(byte) }
        return String(hash, radix: 36) + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension)
    }

    func purgeDisk() {
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
        memory.removeAllObjects()
    }

    func diskSize() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: diskDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// Drop-in replacement for AsyncImage backed by `ImageLoader`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ImageLoader.shared.cached(url)
            if image != nil { return }
            let loaded = await ImageLoader.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}

extension RemoteImage where Placeholder == AnyView {
    init(url: URL?, contentMode: ContentMode = .fill, systemPlaceholder: String = "photo") {
        self.init(url: url, contentMode: contentMode) {
            AnyView(
                ZStack {
                    Theme.posterPlaceholder
                    Image(systemName: systemPlaceholder)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            )
        }
    }
}
