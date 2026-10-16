import Foundation
import MacMDKit

/// Builds the full HTML page shown in Read mode and used for export.
enum ReaderPage {
    static let scheme = "macmd"
    /// Bundled reader assets: `macmd://app/<path in Resources/Web>`.
    static let assetBase = "macmd://app/"

    /// Base URL for a document so relative links and images resolve against its folder:
    /// `macmd://file/<absolute directory path>/`.
    static func baseURL(for directory: URL?) -> URL {
        guard let directory else { return URL(string: "macmd://file/")! }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        // A folder URL's path may already end in "/"; a doubled one would resolve `../` a level too deep.
        var path = directory.standardizedFileURL.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/"
        return components.url ?? URL(string: "macmd://file/")!
    }

    /// `measure` overrides the theme's line width (a CSS length such as `68ch`, or `none`).
    static func html(for rendered: RenderedHTML, theme: Theme.ID, title: String, measure: String? = nil) -> String {
        var head: [String] = [
            #"<meta charset="utf-8">"#,
            #"<meta name="viewport" content="width=device-width, initial-scale=1">"#,
            #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src macmd: data: https: http:; media-src macmd: https:; style-src macmd://app 'unsafe-inline'; font-src macmd://app data:; script-src macmd://app; form-action 'none'; base-uri 'none'; frame-ancestors 'none'">"#,
            "<title>\(escapeHTML(title))</title>",
            stylesheet("reader.css"),
        ]
        if rendered.features.contains(.code) {
            head += [
                stylesheet("vendor/highlight/github.min.css", media: "(prefers-color-scheme: light)"),
                stylesheet("vendor/highlight/github-dark.min.css", media: "(prefers-color-scheme: dark)"),
                script("vendor/highlight/highlight.min.js"),
            ]
        }
        if rendered.features.contains(.math) {
            head += [stylesheet("vendor/katex/katex.min.css"), script("vendor/katex/katex.min.js")]
        }
        if rendered.features.contains(.mermaid) {
            head.append(script("vendor/mermaid/mermaid.min.js"))
        }
        head.append(script("reader.js"))
        return """
            <!doctype html>
            <html lang="en" data-theme="\(theme.rawValue)"\(measure.map { #" style="--measure: \#(escapeHTML($0))""# } ?? "")>
            <head>
            \(head.joined(separator: "\n"))
            </head>
            <body>
            <article class="markdown-body">
            \(rendered.body)
            </article>
            </body>
            </html>
            """
    }

    private static func stylesheet(_ path: String, media: String? = nil) -> String {
        let mediaAttribute = media.map { #" media="\#($0)""# } ?? ""
        return #"<link rel="stylesheet" href="\#(assetBase)\#(path)"\#(mediaAttribute)>"#
    }

    private static func script(_ path: String) -> String {
        #"<script src="\#(assetBase)\#(path)"></script>"#
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }
}
