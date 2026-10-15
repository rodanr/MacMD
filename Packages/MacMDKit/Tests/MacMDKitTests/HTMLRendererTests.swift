import Testing

@testable import MacMDKit

@Suite struct HTMLRendererTests {
    private func html(_ text: String) -> String { HTMLRenderer.render(text).body }

    @Test func headingsGetIDsAndSourceLines() {
        #expect(html("# Hello World") == #"<h1 id="hello-world" data-line="1">Hello World</h1>"#)
    }

    @Test func escapesText() {
        #expect(html("a < b & c") == #"<p data-line="1">a &lt; b &amp; c</p>"#)
    }

    @Test func inlineFormatting() {
        #expect(
            html("**b** *i* ~~s~~ `c<`")
                == #"<p data-line="1"><strong>b</strong> <em>i</em> <del>s</del> <code>c&lt;</code></p>"#)
    }

    @Test func codeBlockWithLanguage() {
        #expect(
            html("```swift\nlet a = \"<\"\n```")
                == #"<pre data-line="1"><code class="language-swift">let a = &quot;&lt;&quot;"# + "\n</code></pre>")
    }

    @Test func mermaidBlockBecomesDiagram() {
        let result = HTMLRenderer.render("```mermaid\ngraph TD; A-->B\n```")
        #expect(result.body.contains(#"<div class="mermaid" data-line="1">graph TD; A--&gt;B"#))
        #expect(result.features.contains(.mermaid))
    }

    @Test func taskListItems() {
        let body = html("- [x] done\n- [ ] todo")
        #expect(body.contains(#"<li class="task" data-line="1"><input type="checkbox" disabled checked> done</li>"#))
        #expect(body.contains(#"<li class="task" data-line="2"><input type="checkbox" disabled> todo</li>"#))
        #expect(body.hasPrefix(#"<ul class="contains-task-list" data-line="1">"#))
    }

    @Test func orderedListStart() {
        #expect(html("3. a\n4. b").hasPrefix(#"<ol start="3" data-line="1">"#))
    }

    @Test func tableWithAlignment() {
        let body = html("| a | b |\n|:--|--:|\n| 1 | 2 |")
        #expect(body.contains(#"<th style="text-align:left">a</th>"#))
        #expect(body.contains(#"<td style="text-align:right">2</td>"#))
    }

    @Test func linksAndImages() {
        #expect(html("[x](https://a.b \"t\")") == #"<p data-line="1"><a href="https://a.b" title="t">x</a></p>"#)
        #expect(html("![alt](img.png)") == #"<p data-line="1"><img src="img.png" alt="alt"></p>"#)
    }

    @Test func mathIsRenderedAsKaTeXPlaceholders() {
        let result = HTMLRenderer.render("Inline $a_b$ math\n\n$$\nx^2\n$$")
        #expect(result.body.contains(#"<span class="math" data-tex="a_b"></span>"#))
        #expect(result.body.contains(#"<div class="math display" data-line="3" data-tex="&#10;x^2&#10;"></div>"#))
        #expect(result.features.contains(.math))
    }

    @Test func codeFeatureDetected() {
        #expect(HTMLRenderer.render("```js\nx\n```").features.contains(.code))
        #expect(HTMLRenderer.render("plain").features.isEmpty)
    }

    @Test func rawHTMLPassesThrough() {
        #expect(html("<details><summary>s</summary>x</details>").contains("<details>"))
    }

    @Test func blockQuoteAndBreaks() {
        #expect(html("> q") == "<blockquote data-line=\"1\">\n<p data-line=\"1\">q</p>\n</blockquote>")
        #expect(html("---") == #"<hr data-line="1">"#)
        #expect(html("a  \nb") == "<p data-line=\"1\">a<br>\nb</p>")
    }
}
