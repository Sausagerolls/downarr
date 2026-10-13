import SwiftUI

enum Theme {
    // Service accents, pulled from each project's own branding.
    static let sonarr = Color(red: 0.21, green: 0.77, blue: 0.94)
    static let radarr = Color(red: 1.00, green: 0.76, blue: 0.19)
    static let jellyfin = Color(red: 0.67, green: 0.36, blue: 0.76)
    static let nzbget = Color(red: 0.16, green: 0.71, blue: 0.40)
    static let deluge = Color(red: 0.31, green: 0.55, blue: 0.93)

    static let positive = Color(red: 0.20, green: 0.78, blue: 0.47)
    static let warning = Color(red: 1.00, green: 0.71, blue: 0.20)
    static let danger = Color(red: 0.96, green: 0.34, blue: 0.36)
    static let neutral = Color.secondary

    static let posterPlaceholder = Color(nsColor: .quaternarySystemFill)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.85), color.opacity(0.45)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let posterAspect: CGFloat = 2.0 / 3.0
}

/// Soft surface used for every panel in the app.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14, radius: CGFloat = 12) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Hairline separator that reads correctly on both themes.
    func hairline(edge: Edge = .bottom) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }
}
