import Testing

@Suite("PanelDismissPolicy")
struct PanelDismissPolicyTests {

    @Test("Started timer dismisses panel")
    func startedTimerDismisses() {
        #expect(PanelDismissPolicy.shouldDismiss(after: .startedTimer(projectId: 1, taskId: 2, description: "test")))
    }

    @Test("Continued timer dismisses panel")
    func continuedTimerDismisses() {
        #expect(PanelDismissPolicy.shouldDismiss(after: .continuedTimer(activityId: 1, projectName: "Test")))
    }

    @Test("Resumed timer dismisses panel")
    func resumedTimerDismisses() {
        #expect(PanelDismissPolicy.shouldDismiss(after: .resumedTimer(activityId: 1, projectName: "Test")))
    }

    @Test("Paused timer stays open")
    func pausedTimerStaysOpen() {
        #expect(!PanelDismissPolicy.shouldDismiss(after: .pausedTimer))
    }

    @Test("Started editing stays open")
    func startedEditingStaysOpen() {
        #expect(!PanelDismissPolicy.shouldDismiss(after: .startedEditing))
    }

    @Test("No-op stays open")
    func noOpStaysOpen() {
        #expect(!PanelDismissPolicy.shouldDismiss(after: .noOp))
    }
}
