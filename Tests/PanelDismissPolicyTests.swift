import XCTest

final class PanelDismissPolicyTests: XCTestCase {

    func testStartedTimerDismisses() {
        let result = PanelDismissPolicy.shouldDismiss(after: .startedTimer(projectId: 1, taskId: 2, description: "test"))
        XCTAssertTrue(result)
    }

    func testContinuedTimerDismisses() {
        let result = PanelDismissPolicy.shouldDismiss(after: .continuedTimer(activityId: 1, projectName: "Test"))
        XCTAssertTrue(result)
    }

    func testResumedTimerDismisses() {
        let result = PanelDismissPolicy.shouldDismiss(after: .resumedTimer(activityId: 1, projectName: "Test"))
        XCTAssertTrue(result)
    }

    func testPausedTimerStaysOpen() {
        let result = PanelDismissPolicy.shouldDismiss(after: .pausedTimer)
        XCTAssertFalse(result)
    }

    func testStartedEditingStaysOpen() {
        let result = PanelDismissPolicy.shouldDismiss(after: .startedEditing)
        XCTAssertFalse(result)
    }

    func testNoOpStaysOpen() {
        let result = PanelDismissPolicy.shouldDismiss(after: .noOp)
        XCTAssertFalse(result)
    }
}
