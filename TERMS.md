# Terms of Use and Privacy

_Last updated: October 15, 2026_

MacMD is free, open-source software made by Rodan Ramdam and contributors. By using it, you agree to these
terms. They are short and they are also shown inside the app under **MacMD → About MacMD → Terms & Privacy**.

## License

MacMD is distributed under the [MIT License](LICENSE). You may use, copy, modify and redistribute it,
including commercially, as long as the copyright notice and license text are kept.

## No warranty

MacMD is provided **"as is", without warranty of any kind**, express or implied, including fitness for a
particular purpose and non-infringement. In no event shall the authors or contributors be liable for any
claim, damages or other liability arising from the use of the software, including loss of data. Keep backups
of documents that matter to you (Time Machine, Git or a sync service). MacMD autosaves and keeps macOS
document versions, but no software is free of bugs.

## Your documents and privacy

- MacMD has **no accounts, analytics, telemetry, advertising or crash reporting**. It does not collect, store,
  sell or share any personal data.
- Your files stay on your Mac. MacMD reads and writes only the documents you open, images you add to them,
  and files you export.
- Settings are stored locally in the macOS defaults system.

MacMD connects to the internet only when you ask it to:

- **Remote images:** when a document you open references an image on the web (`https://…`), Read mode and
  exports load it from that server.
- **Links:** when you click a web link, it opens in your default browser.
- **Check for Updates…:** when you choose it, MacMD asks `api.github.com` for the latest release version.
- **Exported HTML with math:** when you open such a file in a browser, it loads KaTeX fonts from
  `cdn.jsdelivr.net`.

Those services have their own privacy policies.

## Third-party software

MacMD bundles open-source components (swift-markdown, cmark-gfm, highlight.js, KaTeX and Mermaid) under their
own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); the app shows them under
**Acknowledgements**.

## Trademarks

Apple, Mac, macOS and New York are trademarks of Apple Inc. MacMD is an independent project and is not
affiliated with, sponsored by or endorsed by Apple Inc.

## Changes and contact

Changes to these terms are published in this repository and noted in the [changelog](CHANGELOG.md). Questions
and bug reports go to [GitHub Issues](https://github.com/rodanr/MacMD/issues); security reports follow
[SECURITY.md](SECURITY.md).
