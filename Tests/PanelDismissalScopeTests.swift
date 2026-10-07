import Testing
@testable import MocoCompanion

@Suite("Panel dismissal ownership")
@MainActor
struct PanelDismissalScopeTests {
    @Test("Only the originating presentation closes, and only once")
    func ownedDismissal() {
        let panel = PanelDismissalScope()
        let settings = PanelDismissalScope()
        var panelCloses = 0
        var settingsCloses = 0
        panel.beginPresentation { panelCloses += 1 }
        settings.beginPresentation { settingsCloses += 1 }
        let completion = panel.makeDismissAction()
        completion()
        completion()
        #expect(panelCloses == 1)
        #expect(settingsCloses == 0)
    }

    @Test("Hide and reuse invalidate old completion callbacks")
    func reusedPresentation() {
        let scope = PanelDismissalScope()
        var closes = 0
        scope.beginPresentation { closes += 1 }
        let stale = scope.makeDismissAction()
        scope.invalidate()
        stale()
        #expect(closes == 0)
        scope.beginPresentation { closes += 1 }
        stale()
        #expect(closes == 0)
        scope.makeDismissAction()()
        #expect(closes == 1)
    }
}
