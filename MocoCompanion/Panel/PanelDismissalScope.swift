import SwiftUI

/// A close action belongs to one presentation, never to whichever window is key later.
@MainActor
final class PanelDismissalScope {
    private var generation = 0
    private var close: (() -> Void)?

    func beginPresentation(close: @escaping () -> Void) {
        generation &+= 1
        self.close = close
    }

    func invalidate() {
        generation &+= 1
        close = nil
    }

    func makeDismissAction() -> () -> Void {
        let capturedGeneration = generation
        return { [weak self] in
            guard let self, self.generation == capturedGeneration else { return }
            let action = self.close
            self.invalidate()
            action?()
        }
    }
}

private struct PanelDismissalScopeKey: EnvironmentKey {
    static let defaultValue: PanelDismissalScope? = nil
}

extension EnvironmentValues {
    var panelDismissalScope: PanelDismissalScope? {
        get { self[PanelDismissalScopeKey.self] }
        set { self[PanelDismissalScopeKey.self] = newValue }
    }
}
