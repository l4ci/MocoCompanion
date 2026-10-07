import SwiftUI
import AppKit

/// `NSHostingView` that accepts the first mouse click on an inactive window.
///
/// This app is an accessory (menubar) app, so another app is usually
/// frontmost when the user clicks the timeline window. AppKit then uses
/// the first mouse-down only to activate the window and drops it, unless
/// the view under the cursor accepts first mouse. `NSHostingView` does
/// not, so a drag that started with that click never began and a
/// double-click arrived as a single click. Accepting first mouse makes
/// the window behave like Finder or Calendar: the click that activates
/// the window also acts on what was clicked.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
