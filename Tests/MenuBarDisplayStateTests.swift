import XCTest

final class MenuBarDisplayStateTests: XCTestCase {

    func testIdleState() {
        let state = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil, hasError: false)
        XCTAssertEqual(state.iconName, "timer")
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.accessibilityDescription, "Moco Timer")
    }

    func testErrorOverridesIdle() {
        let state = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil, hasError: true)
        XCTAssertEqual(state.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(state.title, "")
    }

    func testErrorOverridesRunning() {
        let state = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "Test"), currentActivity: nil, hasError: true)
        XCTAssertEqual(state.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(state.title, "")
    }

    func testPausedStateShowsIdleLike() {
        let state = MenuBarDisplayState.from(timerState: .paused(activityId: 1, projectName: "Marketing"), currentActivity: nil, hasError: false)
        XCTAssertEqual(state.iconName, "timer")
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.accessibilityDescription, "Timer Paused")
    }

    func testRunningStateShowsTimerIcon() {
        let state = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "Test"), currentActivity: nil, hasError: false)
        XCTAssertEqual(state.iconName, "timer")
        XCTAssertEqual(state.accessibilityDescription, "Timer Running")
    }

    func testEquatable() {
        let a = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil, hasError: false)
        let b = MenuBarDisplayState.from(timerState: .idle, currentActivity: nil, hasError: false)
        XCTAssertEqual(a, b)
    }

    func testPausedAccessibility() {
        let state = MenuBarDisplayState.from(timerState: .paused(activityId: 42, projectName: "Acme"), currentActivity: nil, hasError: false)
        XCTAssertEqual(state.accessibilityDescription, "Timer Paused")
    }

    // MARK: - Truncation

    func testTruncateMiddle() {
        // Short text — no truncation
        let short = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "Hi"), currentActivity: nil, hasError: false)
        XCTAssertTrue(short.title.contains("Hi"))
        XCTAssertFalse(short.title.contains("…") && short.title.contains("·"))
    }

    func testLongProjectAndTaskTruncated() {
        // With a very long project name and no activity, should still fit
        let state = MenuBarDisplayState.from(timerState: .running(activityId: 1, projectName: "This Is A Very Long Project Name That Should Be Truncated"), currentActivity: nil, hasError: false)
        XCTAssertTrue(state.title.contains("…"))
    }
}
