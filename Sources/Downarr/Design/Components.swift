import SwiftUI

// MARK: - Text bits

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var action: (() -> Void)?
    var actionLabel: String = "See all"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var icon: String?
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 10, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(filled ? tint.opacity(0.9) : tint.opacity(0.14))
        )
        .foregroundStyle(filled ? Color.white : tint)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor ?? .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Stats

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String?
    var icon: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.gradient(tint))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

struct ProgressBarView: View {
    var value: Double          // 0...1
    var tint: Color = .accentColor
    var height: CGFloat = 6
    var showsTrack: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if showsTrack {
                    Capsule().fill(Color.primary.opacity(0.09))
                }
                Capsule()
                    .fill(Theme.gradient(tint))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - States

struct EmptyStateView: View {
    var icon: String = "tray"
    let title: String
    var message: String?
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct LoadingOverlay: View {
    var text: String = "Loading…"
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry).buttonStyle(.link).font(.caption)
            }
            if let dismiss {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.danger.opacity(0.10))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.danger).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ToastOverlay: View {
    let toast: Toast

    private var tint: Color {
        switch toast.kind {
        case .success: return Theme.positive
        case .error: return Theme.danger
        case .info: return .accentColor
        }
    }

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(toast.text).font(.callout).lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Posters

struct PosterCard: View {
    let title: String
    var subtitle: String?
    let imageURL: URL?
    var width: CGFloat = 150
    var badge: String?
    var badgeTint: Color = .accentColor
    var progress: Double?
    var progressTint: Color = .accentColor
    var dimmed: Bool = false
    var placeholderIcon: String = "film"

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(url: imageURL, systemPlaceholder: placeholderIcon)
                    .frame(width: width, height: width / Theme.posterAspect)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(alignment: .bottom) {
                        if let progress {
                            ProgressBarView(value: progress, tint: progressTint, height: 4, showsTrack: false)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .padding(5)
                        }
                    }
                    .saturation(dimmed ? 0.25 : 1)
                    .opacity(dimmed ? 0.75 : 1)

                if let badge {
                    Pill(text: badge, tint: badgeTint, filled: true)
                        .padding(6)
                        .shadow(radius: 2)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.28 : 0.12), radius: hovering ? 12 : 4, y: hovering ? 5 : 2)
            .scaleEffect(hovering ? 1.025 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 30, alignment: .top)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .onHover { hovering = $0 }
    }
}

/// Wide backdrop header used at the top of detail screens.
struct DetailHeader<Content: View>: View {
    let backdropURL: URL?
    let posterURL: URL?
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: backdropURL, systemPlaceholder: "photo")
                .frame(height: 260)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.92)],
                        startPoint: .top, endPoint: .bottom)
                )
                .background(Theme.gradient(tint))

            HStack(alignment: .bottom, spacing: 16) {
                RemoteImage(url: posterURL, systemPlaceholder: "film")
                    .frame(width: 120, height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                content()
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(height: 260)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Layout helpers

struct FlowTags: View {
    let tags: [String]
    var tint: Color = .secondary

    var body: some View {
        // A simple wrapping row; tag counts here are small (genres, studios).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { ForEach(tags, id: \.self) { Pill(text: $0, tint: tint) } }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(tags.chunked(3).enumerated()), id: \.offset) { row in
                    HStack(spacing: 4) { ForEach(row.element, id: \.self) { Pill(text: $0, tint: tint) } }
                }
            }
        }
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// Toolbar-style segmented control used for filters.
struct SegmentedPicker<T: Hashable>: View {
    let options: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
