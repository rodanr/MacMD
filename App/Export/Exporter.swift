import AppKit
import MacMDKit
import UniformTypeIdentifiers
import WebKit

/// HTML/PDF export and printing. Each job renders the document in an offscreen web view
/// (light appearance), waits for code, math and diagrams to finish, then saves or prints.
@MainActor
enum Exporter {
    static func exportHTML(markdown: String, directory: URL?, suggestedName: String, window: NSWindow) {
        chooseDestination(type: .html, name: suggestedName, window: window) { url in
            let page = try await OffscreenPage.render(markdown: markdown, directory: directory)
            let html = try await page.standaloneHTML()
            try Data(html.utf8).write(to: url, options: .atomic)
        }
    }

    static func exportPDF(markdown: String, directory: URL?, suggestedName: String, window: NSWindow) {
        chooseDestination(type: .pdf, name: suggestedName, window: window) { url in
            let page = try await OffscreenPage.render(markdown: markdown, directory: directory)
            let printInfo = makePrintInfo()
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            await page.print(printInfo: printInfo, showPanels: false, window: window)
        }
    }

    static func print(markdown: String, baseURL directory: URL?, window: NSWindow) {
        Task {
            do {
                let page = try await OffscreenPage.render(markdown: markdown, directory: directory)
                await page.print(printInfo: makePrintInfo(), showPanels: true, window: window)
            } catch {
                window.presentError(error)
            }
        }
    }

    private static func makePrintInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 54
        info.rightMargin = 54
        return info
    }

    private static func chooseDestination(
        type: UTType, name: String, window: NSWindow, write: @escaping @MainActor (URL) async throws -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await write(url) } catch { window.presentError(error) }
            }
        }
    }
}

/// A fully rendered page in an offscreen web view.
@MainActor
private final class OffscreenPage: NSObject, WKScriptMessageHandler {
    private static var active: Set<OffscreenPage> = []
    private let webView: WKWebView
    private var renderContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(ResourceSchemeHandler(), forURLScheme: ReaderPage.scheme)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000), configuration: configuration)
        webView.appearance = NSAppearance(named: .aqua)
        super.init()
        configuration.userContentController.add(self, name: "macmd")
    }

    static func render(markdown: String, directory: URL?) async throws -> OffscreenPage {
        let page = OffscreenPage()
        active.insert(page)
        let theme = AppSettings.shared.themeID
        let rendered = await Task.detached { HTMLRenderer.render(markdown) }.value
        await withCheckedContinuation { continuation in
            page.renderContinuation = continuation
            page.webView.loadHTMLString(
                ReaderPage.html(for: rendered, theme: theme, title: "Export"),
                baseURL: ReaderPage.baseURL(for: directory))
            // Never wait forever: export whatever has rendered if a script stalls.
            Task { @MainActor [weak page] in
                try? await Task.sleep(for: renderTimeout)
                page?.renderDidFinish()
            }
        }
        return page
    }

    private static let renderTimeout: Duration = .seconds(15)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard (message.body as? [String: Any])?["type"] as? String == "rendered" else { return }
        renderDidFinish()
    }

    private func renderDidFinish() {
        renderContinuation?.resume()
        renderContinuation = nil
    }

    /// The rendered DOM with bundled CSS inlined and scripts removed: a single portable file.
    func standaloneHTML() async throws -> String {
        defer { finish() }
        let html = try await webView.evaluateJavaScript("macmd.exportDocument()") as? String ?? ""
        return Self.inlineStylesheets(in: html)
    }

    func print(printInfo: NSPrintInfo, showPanels: Bool, window: NSWindow) async {
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = showPanels
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
        await withCheckedContinuation { continuation in
            // The operation doesn't retain its delegate; tie the delegate's lifetime to the operation.
            let delegate = PrintDelegate { continuation.resume() }
            objc_setAssociatedObject(operation, &PrintDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
            operation.runModal(
                for: window, delegate: delegate,
                didRun: #selector(PrintDelegate.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil)
        }
        finish()
    }

    private func finish() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "macmd")
        Self.active.remove(self)
    }

    private static func inlineStylesheets(in html: String) -> String {
        let webRoot = Bundle.main.resourceURL?.appending(path: "Web")
        return html.replacing(/<link rel="stylesheet" href="macmd:\/\/app\/([^"]+)"( media="[^"]*")?>/) { match in
            guard let webRoot,
                var css = try? String(contentsOf: webRoot.appending(path: String(match.output.1)), encoding: .utf8)
            else { return "" }
            // KaTeX fonts are not inlined; load them from the matching CDN release.
            css = css.replacingOccurrences(
                of: "url(fonts/", with: "url(https://cdn.jsdelivr.net/npm/katex@\(WebAssets.katexVersion)/dist/fonts/")
            return "<style\(match.output.2 ?? "")>\n\(css)\n</style>"
        }
        .replacing(/<script[^>]*><\/script>\n?/, with: "")
        .replacing(/<meta http-equiv="Content-Security-Policy"[^>]*>\n?/, with: "")
    }
}

private final class PrintDelegate: NSObject {
    nonisolated(unsafe) static var key = 0
    let completion: () -> Void
    init(completion: @escaping () -> Void) { self.completion = completion }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?)
    {
        completion()
    }
}
