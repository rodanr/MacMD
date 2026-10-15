import AppKit
import MacMDKit
import WebKit

/// Owns the Read-mode web view: renders the document, keeps scroll position and routes links.
@MainActor
final class ReaderController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private weak var model: DocumentModel?
    private var renderedRevision = -1
    private var renderedTheme: Theme.ID?
    private var renderedMeasure: String?
    /// The document's location at the last render: relative images and links resolve against it, and a
    /// document opened straight into Read mode only learns it after the first render.
    private var renderedFileURL: URL?
    private var isLoaded = false
    /// Set right before the app loads a page, so only that navigation is allowed.
    private var expectsOwnLoad = false
    /// Source line to show once the page has rendered.
    var pendingLine: Int?
    /// Source line at the top of the reader, reported by the page while scrolling.
    private(set) var lastTopLine: Int?

    init(model: DocumentModel) {
        self.model = model
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(ResourceSchemeHandler(), forURLScheme: ReaderPage.scheme)
        configuration.preferences.isElementFullscreenEnabled = false
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.alphaValue = 0  // revealed once the first render completes, avoiding a white flash
        webView.allowsMagnification = true
        webView.setAccessibilityIdentifier("reader")
        super.init()
        controller.add(WeakScriptMessageHandler(self), name: "macmd")
        webView.navigationDelegate = self
    }

    /// Re-renders when the text, theme, line width or the document's location changed since the last render.
    func refresh(theme: Theme.ID, measure: String) {
        guard let model,
            model.revision != renderedRevision || theme != renderedTheme || measure != renderedMeasure
                || model.fileURL != renderedFileURL
        else {
            if let line = pendingLine, isLoaded { scroll(toLine: line) }
            return
        }
        renderedRevision = model.revision
        renderedTheme = theme
        renderedMeasure = measure
        renderedFileURL = model.fileURL
        isLoaded = false
        if pendingLine == nil { pendingLine = lastTopLine }
        let markdown = model.text
        let title = model.fileURL?.lastPathComponent ?? "Untitled"
        let baseURL = ReaderPage.baseURL(for: model.fileURL?.deletingLastPathComponent())
        let revision = model.revision
        let fileURL = model.fileURL
        Task {
            let rendered = await Task.detached(priority: .userInitiated) { HTMLRenderer.render(markdown) }.value
            // A newer render may have started meanwhile; never load stale output.
            guard revision == renderedRevision, theme == renderedTheme, measure == renderedMeasure,
                fileURL == renderedFileURL
            else { return }
            expectsOwnLoad = true
            webView.loadHTMLString(
                ReaderPage.html(for: rendered, theme: theme, title: title, measure: measure), baseURL: baseURL)
            try? await Task.sleep(for: .seconds(3))
            reveal()  // fallback in case the page never reports "rendered"
        }
    }

    func scroll(toLine line: Int) {
        pendingLine = nil
        webView.evaluateJavaScript("window.macmd && macmd.scrollToLine(\(line))")
    }

    func scroll(toAnchor slug: String) {
        guard let data = try? JSONEncoder().encode(slug), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.macmd && macmd.scrollToAnchor(\(json))")
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "rendered":
            isLoaded = true
            reveal()
            if let line = pendingLine { scroll(toLine: line) }
        case "topLine":
            lastTopLine = body["line"] as? Int
            model?.readerTopLine = lastTopLine
        default:
            break
        }
    }

    private func reveal() {
        guard webView.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.12; webView.animator().alphaValue = 1
        }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame ?? true else {
            return .cancel
        }
        if expectsOwnLoad {
            expectsOwnLoad = false
            return .allow
        }
        // In-page anchors scroll inside the reader.
        if url.fragment != nil, url.scheme == ReaderPage.scheme,
            url.path(percentEncoded: false) == webView.url?.path(percentEncoded: false)
        {
            return .allow
        }
        // Nothing else (clicked links, meta refresh, forms, scripts) may replace the document.
        if navigationAction.navigationType == .linkActivated { LinkRouter.open(url) }
        return .cancel
    }
}

/// Avoids the retain cycle between `WKUserContentController` and its handler.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Opens links clicked in documents: Markdown files in MacMD, everything else in its default app.
@MainActor
enum LinkRouter {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// Web links open in the browser and local Markdown opens in MacMD. Other local files are only
    /// revealed in Finder, so a link in a document can never launch an app or a script.
    static func open(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == ReaderPage.scheme, url.host() == "file" {
            openFile(URL(filePath: url.path(percentEncoded: false)))
        } else if scheme == "file" {
            openFile(url)
        } else if webSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
        }
    }

    /// `browsing` is the folder of the Files sidebar the file was opened from; the new document keeps
    /// browsing it, so moving between files doesn't lose your place.
    static func openFile(_ fileURL: URL, browsing folder: URL? = nil) {
        if markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { document, _, _ in
                guard let folder, let document = document as? MarkdownDocument,
                    fileURL.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
                else { return }
                document.model.browsedFolder = folder
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }
}
