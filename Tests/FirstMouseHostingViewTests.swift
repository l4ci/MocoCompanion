import Testing
import SwiftUI
@testable import MocoCompanion

@Suite("FirstMouseHostingView")
struct FirstMouseHostingViewTests {
    @Test("accepts the first mouse click so an activating click still acts")
    @MainActor func acceptsFirstMouse() {
        let view = FirstMouseHostingView(rootView: Text("probe"))
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    @Test("plain NSHostingView does not, which is the behaviour being replaced")
    @MainActor func plainHostingViewDoesNot() {
        let view = NSHostingView(rootView: Text("probe"))
        #expect(view.acceptsFirstMouse(for: nil) == false)
    }
}
