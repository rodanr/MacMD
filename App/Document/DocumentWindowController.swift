import AppKit
import SwiftUI

/// Hosts the SwiftUI document UI in a standard document window.
final class DocumentWindowController: NSWindowController {
    init(document: MarkdownDocument) {
        let hosting = NSHostingController(rootView: DocumentView(model: document.model))
        hosting.sceneBridgingOptions = [.toolbars]
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.setContentSize(NSSize(width: 1040, height: 760))
        window.minSize = NSSize(width: 520, height: 360)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
        windowFrameAutosaveName = "MarkdownDocumentWindow"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
