import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves `macmd://app/…` from the bundled `Web` folder and `macmd://file/…` (images and media only)
/// from disk, so the reader works offline and can show pictures stored next to the document.
@MainActor
final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let webRoot = Bundle.main.resourceURL?.appending(path: "Web", directoryHint: .isDirectory)
        .standardizedFileURL
    /// Tasks WebKit has stopped; they must not receive further callbacks.
    private var stoppedTasks: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let (fileURL, type) = resolve(url) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let id = ObjectIdentifier(task)
        Task {
            // Read off the main thread so large images never stall the UI.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Data(contentsOf: fileURL, options: .mappedIfSafe) }
            }.value
            guard stoppedTasks.remove(id) == nil else { return }
            switch result {
            case .success(let data):
                let mime = type.preferredMIMEType ?? "application/octet-stream"
                let response =
                    HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": mime, "Content-Length": String(data.count)])
                    ?? URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            case .failure(let error):
                task.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(task))
    }

    private func resolve(_ url: URL) -> (URL, UTType)? {
        let path = url.path(percentEncoded: false)
        switch url.host() {
        case "app":
            guard let webRoot else { return nil }
            let resolved = webRoot.appending(path: path).standardizedFileURL
            // Never serve anything outside the bundled web folder.
            guard resolved.path.hasPrefix(webRoot.path + "/") else { return nil }
            return (resolved, UTType(filenameExtension: resolved.pathExtension) ?? .data)
        case "file":
            // Documents may embed media, never read arbitrary files.
            let fileURL = URL(filePath: path).standardizedFileURL
            guard let type = UTType(filenameExtension: fileURL.pathExtension),
                type.conforms(to: .image) || type.conforms(to: .audiovisualContent)
            else { return nil }
            return (fileURL, type)
        default:
            return nil
        }
    }
}
