import SwiftUI
import WebKit

/// SwiftUI host for the reader's web view. The controller outlives mode switches.
struct ReaderView: NSViewRepresentable {
    let controller: ReaderController
    let theme: Theme.ID
    let revision: Int
    /// The window zoom, so ⌘+ / ⌘- scale Read mode like everything else.
    let zoom: Double
    /// The line width as a CSS length (`68ch`) or `none`.
    let measure: String
    let isVisible: Bool

    func makeNSView(context: Context) -> WKWebView {
        controller.webView.pageZoom = zoom
        if isVisible { controller.refresh(theme: theme, measure: measure) }
        return controller.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoom
        guard isVisible else { return }
        controller.refresh(theme: theme, measure: measure)
        // Take keyboard focus from the (hidden, read-only) editor once the web view is in the window.
        DispatchQueue.main.async {
            if let window = webView.window, window.firstResponder is NSTextView {
                window.makeFirstResponder(webView)
            }
        }
    }
}
