import Foundation

/// Lightweight request lifecycle used by every store.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
    var errorMessage: String? {
        if case .failed(let m) = self { return m }
        return nil
    }
}

/// A transient message surfaced in the UI (success/failure of an action).
struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    var kind: Kind
    var text: String
    var date = Date()
}
