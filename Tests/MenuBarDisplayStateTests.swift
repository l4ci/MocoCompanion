import Testing
@testable import MocoCompanion

@Suite("MenuBarDisplayState")
struct MenuBarDisplayStateTests {

    @Test("Idle state shows timer icon with empty title")
    func idleState() {
        let state = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil)
        #expect(state.iconName == "timer")
        #expect(state.title == "")
        #expect(state.accessibilityDescription == "Moco Timer")
    }

@Test("Paused state shows idle-like appearance")
    func pausedStateShowsIdleLike() {
        let state = MenuBarDisplayState.from(timerState: .paused(activityId: 1, projectName: "Marketing"), currentActivity: nil)
        #expect(state.iconName == "timer")
        #expect(state.title == "")
        #expect(state.accessibilityDescription == "Timer Paused")
    }

    @Test("Running state shows timer icon")
    func runningStateShowsTimerIcon() {
        let state = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "Test"), currentActivity: nil)
        #expect(state.iconName == "timer")
        #expect(state.accessibilityDescription == "Timer Running")
    }

    @Test("Equatable conformance works")
    func equatable() {
        let a = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil)
        let b = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil)
        #expect(a == b)
    }

    @Test("Paused accessibility description")
    func pausedAccessibility() {
        let state = MenuBarDisplayState.from(timerState: .paused(activityId: 42, projectName: "Acme"), currentActivity: nil)
        #expect(state.accessibilityDescription == "Timer Paused")
    }

    @Test("Short project name is not truncated")
    func truncateMiddle() {
        let short = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "Hi"), currentActivity: nil)
        #expect(short.title.contains("Hi"))
        #expect(!(short.title.contains("…") && short.title.contains("·")))
    }

    @Test("Long project name is truncated")
    func longProjectAndTaskTruncated() {
        let state = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "This Is A Very Long Project Name That Should Be Truncated"), currentActivity: nil)
        #expect(state.title.contains("…"))
    }
}
