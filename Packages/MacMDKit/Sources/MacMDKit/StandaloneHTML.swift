import Foundation

/// Turns the rendered reader page into a single portable HTML file for export.
///
/// Exported files open in any browser, outside MacMD's protections, so they carry their own Content
/// Security Policy: no scripts of any kind (event handlers and `javascript:` links included), while
/// styles, images and KaTeX fonts still load. Code, math and diagrams are already rendered to HTML/SVG.
public enum StandaloneHTML {
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src * data: blob:; media-src *; style-src 'unsafe-inline'; "
        + "font-src https://cdn.jsdelivr.net data:; form-action 'none'; base-uri 'none'"

    /// - Parameters:
    ///   - html: the page's DOM as HTML.
    ///   - stylesheet: returns the CSS for a bundled stylesheet path (`reader.css`), or nil to drop it.
    public static func make(from html: String, stylesheet: (String) -> String?) -> String {
        var result = html.replacing(
            /<link rel="stylesheet" href="macmd:\/\/app\/([^"]+)"( media="[^"]*")?>/
        ) { match in
            guard let css = stylesheet(String(match.output.1)) else { return "" }
            return "<style\(match.output.2 ?? "")>\n\(css)\n</style>"
        }
        // The page's scripts are removed before export; remove any left, whatever their case or content.
        result = result.replacing(/(?is)<script\b.*?<\/script\s*>\n?/, with: "")
        let policy = #"<meta http-equiv="Content-Security-Policy" content="\#(contentSecurityPolicy)">"#
        if result.contains(/<meta http-equiv="Content-Security-Policy"[^>]*>/) {
            result = result.replacing(/<meta http-equiv="Content-Security-Policy"[^>]*>/) { _ in policy }
        } else if let head = result.firstRange(of: /<head[^>]*>/) {
            result.insert(contentsOf: "\n" + policy, at: head.upperBound)
        } else {
            result = policy + "\n" + result
        }
        return result
    }
}
