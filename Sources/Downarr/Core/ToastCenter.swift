import SwiftUI

/// App-wide transient notifications. Stores post here instead of each owning its own banner.
@MainActor
final class ToastCenter: ObservableObject {
    @Published var current: Toast?

    private var dismissTask: Task<Void, Never>?

    func success(_ text: String) { show(Toast(kind: .success, text: text)) }
    func error(_ text: String) { show(Toast(kind: .error, text: text)) }
    func info(_ text: String) { show(Toast(kind: .info, text: text)) }

    func show(_ toast: Toast) {
        current = toast
        dismissTask?.cancel()
        let seconds: UInt64 = toast.kind == .error ? 7 : 3
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
