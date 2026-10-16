import XCTest

/// Moving between files (links, the Files sidebar, New) keeps the folder you're working in, and new Markdown
/// files can be created where you are.
final class FileNavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Writes `files` (paths relative to a fresh folder, subfolders created as needed) and returns the folder.
    private func makeFolder(_ files: [String: String]) throws -> URL {
        let folder = try temporaryFolder()
        for (path, text) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return folder
    }

    /// Opens `file` with the Files sidebar showing.
    private func open(_ file: URL, readMode: Bool = false) -> (XCUIApplication, XCUIElement) {
        let app = launch([
            file.path, "-sidebarVisible", "YES", "-sidebarTab", "files", "-openInReadMode", readMode ? "YES" : "NO",
        ])
        let window = app.windows[file.lastPathComponent]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        return (app, window)
    }

    /// Answers the name prompt (New File, New Folder, Rename).
    private func answerNamePrompt(_ app: XCUIApplication, with name: String) {
        let prompt = app.dialogs["name-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "the name prompt opens")
        let field = prompt.textFields["name-field"]
        field.typeKey("a", modifierFlags: .command)
        field.typeText(name + "\n")
    }

    // MARK: Links

    @MainActor
    func testLinkIntoASubfolderKeepsTheBrowsedFolder() throws {
        let folder = try makeFolder([
            "index.md": "# Index\n\nRead the [setup guide](guide/setup.md).",
            "guide/setup.md": "# Setup",
        ])
        let (app, window) = open(folder.appending(path: "index.md"), readMode: true)
        let link = window.webViews.firstMatch.links["setup guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["setup.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "the linked file opens")
        XCTAssertTrue(
            opened.buttons["index.md"].waitForExistence(timeout: 5),
            "the Files sidebar still browses the folder the link came from")
        attach(opened, "link-keeps-folder")
        app.terminate()
    }

    @MainActor
    func testLinkToAParentFolderBrowsesIt() throws {
        let folder = try makeFolder([
            "index.md": "# Index",
            "guide/setup.md": "# Setup\n\nBack to the [index](../index.md).",
        ])
        let (app, window) = open(folder.appending(path: "guide/setup.md"), readMode: true)
        let link = window.webViews.firstMatch.links["index"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["index.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        XCTAssertTrue(opened.buttons["index.md"].waitForExistence(timeout: 5), "the parent folder is browsed")
        app.terminate()
    }

    @MainActor
    func testLinkToASectionOpensTheFileThere() throws {
        let filler = (1...80).map { "Paragraph \($0) of filler text." }.joined(separator: "\n\n")
        let folder = try makeFolder([
            "a.md": "# A\n\nSee [the setup section](b.md#setup).",
            "b.md": "# B\n\n\(filler)\n\n## Setup\n\nThe steps.",
        ])
        let (app, window) = open(folder.appending(path: "a.md"), readMode: true)
        let link = window.webViews.firstMatch.links["the setup section"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["b.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        let heading = opened.webViews.firstMatch.staticTexts["Setup"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { opened.frame.contains(heading.frame) }, "b.md opens scrolled to the section")
        app.terminate()
    }

    @MainActor
    func testLinkToASectionPlacesTheCaretThereInEditMode() throws {
        let filler = (1...80).map { "Paragraph \($0) of filler text." }.joined(separator: "\n\n")
        let folder = try makeFolder([
            "a.md": "# A\n\nSee [the setup section](b.md#setup).",
            "b.md": "# B\n\n\(filler)\n\n## Setup\n\nThe steps.",
        ])
        // Documents open in Edit mode; the link is followed from Read mode.
        let (app, window) = open(folder.appending(path: "a.md"))
        window.radioButtons["Read"].firstMatch.click()
        let link = window.webViews.firstMatch.links["the setup section"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["b.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        let setupLine = "# B\n\n\(filler)\n\n## Setup".components(separatedBy: "\n").count
        let caret = opened.staticTexts["Ln \(setupLine), Col 1"]
        XCTAssertTrue(caret.waitForExistence(timeout: 10), "the caret is on the Setup heading")
        app.terminate()
    }

    @MainActor
    func testLinkToAMissingFileShowsAnError() throws {
        let folder = try makeFolder(["a.md": "# A\n\nThis [link is broken](gone.md)."])
        let (app, window) = open(folder.appending(path: "a.md"), readMode: true)
        let link = window.webViews.firstMatch.links["link is broken"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let alert = app.dialogs.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "a missing file is reported instead of nothing happening")
        alert.buttons.firstMatch.click()
        XCTAssertTrue(window.exists)
        app.terminate()
    }

    // MARK: New files

    @MainActor
    func testNewFileInFolderCreatesAFileNextToTheDocument() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let (app, _) = open(folder.appending(path: "a.md"))
        app.typeKey("n", modifierFlags: [.command, .option])
        answerNamePrompt(app, with: "sibling")

        let created = folder.appending(path: "sibling.md")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: created.path) }, "sibling.md is created")
        let opened = app.windows["sibling.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "and opened")
        XCTAssertTrue(opened.buttons["a.md"].waitForExistence(timeout: 5), "in the same folder")
        let editor = opened.textViews["editor"]
        editor.typeText("Hello")
        XCTAssertTrue(waitUntil { editor.value as? String == "Hello" }, "ready to type")
        app.terminate()
    }

    @MainActor
    func testFilesSidebarCreatesANewFile() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let (app, window) = open(folder.appending(path: "a.md"))
        let newFile = window.buttons["New File"]
        XCTAssertTrue(newFile.waitForExistence(timeout: 5))
        newFile.click()
        answerNamePrompt(app, with: "notes")

        let opened = app.windows["notes.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "notes.md opens")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "notes.md").path))
        // A background tab isn't visible to UI tests, so check the new window's list: it has both files.
        XCTAssertTrue(opened.buttons["notes.md"].waitForExistence(timeout: 5), "the list shows the new file")
        XCTAssertTrue(opened.buttons["a.md"].exists, "in the same folder")
        attach(opened, "files-new-file")
        app.terminate()
    }

    @MainActor
    func testNewFileNameThatExistsIsRefused() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let (app, _) = open(folder.appending(path: "a.md"))
        app.typeKey("n", modifierFlags: [.command, .option])
        answerNamePrompt(app, with: "a")
        let message = app.dialogs.staticTexts.matching(NSPredicate(format: "value CONTAINS 'already exists'"))
        XCTAssertTrue(waitUntil { message.count > 0 }, "an error says the name is taken")
        app.dialogs.firstMatch.buttons["OK"].click()
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "a.md"), encoding: .utf8), "# A", "a.md is kept")
        app.terminate()
    }

    @MainActor
    func testOpenPanelCanCreateANewFile() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let app = launch([])
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("o", modifierFlags: .command)
        // The system Open panel's own accessibility identifier.
        let panel = app.windows["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        XCTAssertTrue(waitUntil { panel.textFields["a.md"].exists }, "the panel shows the folder")
        panel.buttons["New File Here…"].click()
        answerNamePrompt(app, with: "from-open")

        XCTAssertTrue(app.windows["from-open.md"].waitForExistence(timeout: 10), "the new file opens")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "from-open.md").path))
        app.terminate()
    }

    @MainActor
    func testNewDocumentStartsInTheCurrentFolder() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let (app, _) = open(folder.appending(path: "a.md"))
        app.typeKey("n", modifierFlags: .command)
        let untitled = app.windows["Untitled"]
        XCTAssertTrue(untitled.waitForExistence(timeout: 10))
        XCTAssertTrue(untitled.buttons["a.md"].waitForExistence(timeout: 5), "the new document browses the folder")

        let editor = untitled.textViews["editor"]
        editor.click()
        editor.typeText("# Fresh")
        editor.typeKey("s", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let nameField = sheet.textFields.firstMatch
        nameField.doubleClick()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("fresh\n")
        let saved = folder.appending(path: "fresh.md")
        XCTAssertTrue(
            waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: saved.path) },
            "Save suggests the folder you were working in")
        app.terminate()
    }

    // MARK: The file list

    @MainActor
    func testFilesListFollowsChangesOnDisk() throws {
        let folder = try makeFolder(["a.md": "# A"])
        let (app, window) = open(folder.appending(path: "a.md"))
        XCTAssertTrue(window.buttons["a.md"].waitForExistence(timeout: 5))

        let later = folder.appending(path: "later.md")
        try "# Later".write(to: later, atomically: true, encoding: .utf8)
        XCTAssertTrue(window.buttons["later.md"].waitForExistence(timeout: 5), "a new file appears")
        try FileManager.default.removeItem(at: later)
        XCTAssertTrue(waitUntil { !window.buttons["later.md"].exists }, "a deleted file disappears")
        app.terminate()
    }

    // MARK: Revealing the current file and acting on rows

    @MainActor
    func testLinkedFileIsRevealedInTheFilesSidebar() throws {
        let folder = try makeFolder([
            "index.md": "# Index\n\nRead the [setup guide](guide/deep/setup.md).",
            "guide/deep/setup.md": "# Setup",
            "guide/other.md": "# Other",
        ])
        let (app, window) = open(folder.appending(path: "index.md"), readMode: true)
        let link = window.webViews.firstMatch.links["setup guide"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["setup.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        let row = opened.buttons["setup.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the folders down to the file are expanded")
        XCTAssertTrue(row.isSelected, "and the file is highlighted")
        XCTAssertTrue(opened.buttons["index.md"].exists, "the root stays the same")
        attach(opened, "files-revealed")
        app.terminate()
    }

    @MainActor
    func testTheFolderYouWereInStaysOpenWhenYouOpenAFileOutsideIt() throws {
        let folder = try makeFolder([
            "index.md": "# Index",
            "guide/setup.md": "# Setup\n\nBack to the [index](../index.md).",
        ])
        // Opened directly, so the Files sidebar browses guide/.
        let (app, window) = open(folder.appending(path: "guide/setup.md"), readMode: true)
        let link = window.webViews.firstMatch.links["index"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()

        let opened = app.windows["index.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        XCTAssertTrue(opened.buttons["guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(opened.buttons["setup.md"].exists, "guide, where you were, stays open")
        app.terminate()
    }

    @MainActor
    func testNewFileGoesIntoTheCurrentFilesFolder() throws {
        let folder = try makeFolder(["index.md": "# Index", "guide/setup.md": "# Setup"])
        let (app, window) = open(folder.appending(path: "index.md"))
        let folderRow = window.buttons["guide"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        folderRow.click()
        XCTAssertTrue(window.buttons["setup.md"].waitForExistence(timeout: 5), "clicking a folder opens it")
        window.buttons["setup.md"].click()

        let opened = app.windows["setup.md"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10))
        opened.buttons["New File"].click()
        answerNamePrompt(app, with: "next")
        let created = folder.appending(path: "guide/next.md")
        XCTAssertTrue(
            waitUntil { FileManager.default.fileExists(atPath: created.path) },
            "New File creates next to the file you're in, not in the root")
        XCTAssertTrue(app.windows["next.md"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    func testNewFileGoesIntoTheSelectedFolder() throws {
        let folder = try makeFolder(["index.md": "# Index", "docs/a.md": "# A"])
        let (app, window) = open(folder.appending(path: "index.md"))
        let folderRow = window.buttons["docs"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        folderRow.click()
        window.buttons["New File"].click()
        answerNamePrompt(app, with: "chosen")
        XCTAssertTrue(
            waitUntil { FileManager.default.fileExists(atPath: folder.appending(path: "docs/chosen.md").path) },
            "New File creates in the folder you clicked")
        app.terminate()
    }

    @MainActor
    func testNewFolderThenNewFileInside() throws {
        let folder = try makeFolder(["index.md": "# Index", "docs/a.md": "# A"])
        let (app, window) = open(folder.appending(path: "index.md"))
        let docs = window.buttons["docs"]
        XCTAssertTrue(docs.waitForExistence(timeout: 5))
        docs.rightClick()
        window.menuItems["New Folder…"].click()
        answerNamePrompt(app, with: "drafts")
        let drafts = folder.appending(path: "docs/drafts")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: drafts.path) }, "the folder is created")
        XCTAssertTrue(window.buttons["drafts"].waitForExistence(timeout: 5), "and shown, opened")

        window.buttons["New File"].click()
        answerNamePrompt(app, with: "idea")
        XCTAssertTrue(
            waitUntil { FileManager.default.fileExists(atPath: drafts.appending(path: "idea.md").path) },
            "the new folder is selected, so New File goes into it")
        app.terminate()
    }

    @MainActor
    func testRenameFromTheSidebarFollowsTheOpenDocument() throws {
        let folder = try makeFolder(["a.md": "# A", "other.md": "# Other"])
        let (app, window) = open(folder.appending(path: "a.md"))
        let row = window.buttons["a.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        window.menuItems["Rename…"].click()
        answerNamePrompt(app, with: "b")
        let renamed = folder.appending(path: "b.md")
        XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: renamed.path) }, "b.md exists")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "a.md").path))
        XCTAssertTrue(app.windows["b.md"].waitForExistence(timeout: 10), "the open document follows the rename")
        app.terminate()
    }

    @MainActor
    func testMoveToTrashAsksFirst() throws {
        let folder = try makeFolder(["a.md": "# A", "old.md": "# Old"])
        let (app, window) = open(folder.appending(path: "a.md"))
        let old = folder.appending(path: "old.md")
        let row = window.buttons["old.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.rightClick()
        window.menuItems["Move to Trash"].click()
        let confirm = app.dialogs.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "it asks first")
        confirm.buttons["Cancel"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path), "Cancel keeps the file")

        row.rightClick()
        window.menuItems["Move to Trash"].click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.buttons["Move to Trash"].click()
        XCTAssertTrue(waitUntil { !FileManager.default.fileExists(atPath: old.path) }, "the file goes to the Trash")
        XCTAssertTrue(waitUntil { !window.buttons["old.md"].exists }, "and leaves the list")
        app.terminate()
    }

    // MARK: Code folders

    /// A repository whose Markdown is in a few places only.
    private func makeCodeFolder() throws -> URL {
        try makeFolder([
            "README.md": "# Project", "docs/guide.md": "# Guide", "src/main.swift": "print(1)",
            "src/util/helpers.swift": "", "node_modules/pkg/readme.md": "# Dependency",
        ])
    }

    @MainActor
    func testFoldersWithoutMarkdownAreQuietAndListedLast() throws {
        let folder = try makeCodeFolder()
        let (app, window) = open(folder.appending(path: "README.md"))
        let docs = window.buttons["docs"]
        let src = window.buttons["src"]
        XCTAssertTrue(src.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil { src.value as? String == "No Markdown files" }, "src is marked as having no Markdown")
        XCTAssertTrue(
            window.buttons["node_modules"].value as? String == "No Markdown files", "dependencies don't count")
        XCTAssertNotEqual(docs.value as? String, "No Markdown files")
        XCTAssertLessThan(docs.frame.minY, src.frame.minY, "folders with Markdown come first")
        attach(window, "files-code-folder")

        // Still usable: create a file in it, and it stops being quiet.
        src.rightClick()
        window.menuItems["New File…"].click()
        answerNamePrompt(app, with: "notes")
        XCTAssertTrue(app.windows["notes.md"].waitForExistence(timeout: 10))
        let srcNow = app.windows["notes.md"].buttons["src"]
        XCTAssertTrue(srcNow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { srcNow.value as? String != "No Markdown files" }, "src now holds Markdown")
        app.terminate()
    }

    @MainActor
    func testFilterFindsMarkdownFilesByName() throws {
        let folder = try makeCodeFolder()
        let (app, window) = open(folder.appending(path: "README.md"))
        let filter = window.textFields["files-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        filter.typeText("guide")
        let result = window.buttons["guide.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "the filter lists matching files from any folder")
        XCTAssertFalse(window.buttons["src"].exists, "the tree is replaced by the results")
        attach(window, "files-filter")

        filter.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(window.buttons["src"].waitForExistence(timeout: 5), "Esc clears the filter")

        filter.typeText("guide")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        XCTAssertTrue(app.windows["guide.md"].waitForExistence(timeout: 10), "a result opens")
        app.terminate()
    }
}
