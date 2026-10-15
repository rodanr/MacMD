import Observation
import SwiftUI

/// A short-lived message confirming a change that is otherwise easy to miss, such as the zoom
/// or a mode switch. Shown at the bottom of the key window.
@MainActor @Observable
final class HUD {
    static let shared = HUD()

    private(set) var message: String?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct HUDView: View {
    @State private var hud = HUD.shared
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.zoom) private var zoom

    var body: some View {
        ZStack {
            if let message = hud.message, activeState == .key {
                Text(message)
                    .font(.system(size: 13 * zoom, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityIdentifier("hud")
            }
        }
        .animation(.easeOut(duration: 0.18), value: hud.message)
        .allowsHitTesting(false)
    }
}
