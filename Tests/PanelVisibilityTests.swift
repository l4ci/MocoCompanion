import XCTest
@testable import MocoCompanion

@MainActor
final class PanelVisibilityTests: XCTestCase {

    func testInitiallyHidden() {
        let vis = PanelVisibility()
        XCTAssertFalse(vis.isVisible)
    }

    func testSetUpdatesIsVisible() {
        let vis = PanelVisibility()
        vis.set(true)
        XCTAssertTrue(vis.isVisible)
        vis.set(false)
        XCTAssertFalse(vis.isVisible)
    }

    func testChangesStreamYieldsCurrentThenUpdates() async {
        let vis = PanelVisibility()
        vis.set(true)

        // Kick off subscription on the current task; collect the first two
        // values (initial + one change) and assert.
        let streamTask = Task { @MainActor in
            var received: [Bool] = []
            for await value in vis.changes {
                received.append(value)
                if received.count == 2 { break }
            }
            return received
        }

        // Give the subscription a beat to register before we publish.
        try? await Task.sleep(for: .milliseconds(20))
        vis.set(false)

        let values = await streamTask.value
        XCTAssertEqual(values, [true, false])
    }

    func testDuplicateSetIsIgnored() async {
        let vis = PanelVisibility()

        let streamTask = Task { @MainActor in
            var received: [Bool] = []
            for await value in vis.changes {
                received.append(value)
                if received.count == 3 { break }
            }
            return received
        }

        try? await Task.sleep(for: .milliseconds(20))
        vis.set(true)      // first real change
        vis.set(true)      // duplicate — must be suppressed
        vis.set(false)     // second real change
        vis.set(false)     // duplicate — must be suppressed

        // Expect: [false (initial), true, false] — duplicates collapsed.
        let values = await streamTask.value
        XCTAssertEqual(values, [false, true, false])
    }

    func testMultipleSubscribersEachReceiveInitialValue() async {
        let vis = PanelVisibility()
        vis.set(true)

        let taskA = Task { @MainActor in
            var received: [Bool] = []
            for await value in vis.changes {
                received.append(value)
                break
            }
            return received
        }

        let taskB = Task { @MainActor in
            var received: [Bool] = []
            for await value in vis.changes {
                received.append(value)
                break
            }
            return received
        }

        let ra = await taskA.value
        let rb = await taskB.value
        XCTAssertEqual(ra, [true])
        XCTAssertEqual(rb, [true])
    }
}
