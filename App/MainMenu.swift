import AppKit

/// The application's main menu, built in code so every item is visible and reviewable.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        for menu in [appMenu(), fileMenu(), editMenu(), formatMenu(), viewMenu(), windowMenu(), helpMenu()] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "MacMD")
        menu.addItem(withTitle: "About MacMD", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide MacMD", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        // NSDocumentController fills this menu because it contains the clear action.
        recentMenu.addItem(
            withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""
        )
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Move To…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Revert to Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Export as HTML…", #selector(MarkdownDocument.exportHTML(_:)), "e", [.command, .shift]))
        menu.addItem(item("Export as PDF…", #selector(MarkdownDocument.exportPDF(_:)), "e", [.command, .option]))
        menu.addItem(
            item("Copy as HTML", #selector(MarkdownDocument.copyAsHTML(_:)), "c", [.command, .option, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(findItem("Find…", .showFindInterface, "f", [.command]))
        find.addItem(findItem("Find and Replace…", .showReplaceInterface, "f", [.command, .option]))
        find.addItem(findItem("Find Next", .nextMatch, "g", [.command]))
        find.addItem(findItem("Find Previous", .previousMatch, "g", [.command, .shift]))
        find.addItem(findItem("Use Selection for Find", .setSearchString, "", []))
        menu.addItem(submenu("Find", find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(
            withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spelling.addItem(
            withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spelling.addItem(
            withTitle: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
            keyEquivalent: "")
        menu.addItem(submenu("Spelling and Grammar", spelling))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(withTitle: "Bold", action: #selector(MarkdownTextView.toggleBold(_:)), keyEquivalent: "b")
        menu.addItem(withTitle: "Italic", action: #selector(MarkdownTextView.toggleItalic(_:)), keyEquivalent: "i")
        menu.addItem(
            item("Strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift]))
        menu.addItem(item("Inline Code", #selector(MarkdownTextView.toggleInlineCode(_:)), "k", [.command, .shift]))
        menu.addItem(withTitle: "Link", action: #selector(MarkdownTextView.insertLink(_:)), keyEquivalent: "k")
        menu.addItem(.separator())

        let headings = NSMenu(title: "Heading")
        // ⌘0 is Actual Size, as in Safari and Notes; Paragraph takes ⌥⌘0.
        let paragraph = item("Paragraph", #selector(MarkdownTextView.setHeadingLevel(_:)), "0", [.command, .option])
        paragraph.tag = 0
        headings.addItem(paragraph)
        for level in 1...6 {
            let heading = headings.addItem(
                withTitle: "Heading \(level)", action: #selector(MarkdownTextView.setHeadingLevel(_:)),
                keyEquivalent: "\(level)")
            heading.tag = level
        }
        menu.addItem(submenu("Heading", headings))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Read Mode", action: #selector(MarkdownDocument.toggleReadMode(_:)), keyEquivalent: "e")
        menu.addItem(.separator())
        menu.addItem(
            item("Show Sidebar", #selector(MarkdownDocument.toggleDocumentSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Outline", #selector(MarkdownDocument.showOutline(_:)), "1", [.command, .control]))
        menu.addItem(item("Files", #selector(MarkdownDocument.showFiles(_:)), "2", [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Focus Mode", #selector(MarkdownDocument.toggleFocusMode(_:)),
                String(Character(UnicodeScalar(NSF8FunctionKey)!)), []))
        menu.addItem(
            item(
                "Typewriter Mode", #selector(MarkdownDocument.toggleTypewriterMode(_:)),
                String(Character(UnicodeScalar(NSF9FunctionKey)!)), []))
        menu.addItem(.separator())
        let themes = NSMenu(title: "Theme")
        for theme in Theme.ID.allCases {
            let themeItem = themes.addItem(
                withTitle: theme.displayName, action: #selector(AppDelegate.setTheme(_:)), keyEquivalent: "")
            themeItem.representedObject = theme.rawValue
        }
        menu.addItem(submenu("Theme", themes))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zoom In", action: #selector(AppDelegate.zoomIn(_:)), keyEquivalent: "=")
        // ⌘+ (Shift-=) also zooms in, as in Safari and Notes.
        let zoomInPlus = item("Zoom In", #selector(AppDelegate.zoomIn(_:)), "+", [.command])
        zoomInPlus.isHidden = true
        zoomInPlus.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInPlus)
        menu.addItem(withTitle: "Zoom Out", action: #selector(AppDelegate.zoomOut(_:)), keyEquivalent: "-")
        menu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.resetZoom(_:)), keyEquivalent: "0")
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "MacMD Help", action: #selector(AppDelegate.openHelp(_:)), keyEquivalent: "?")
        menu.addItem(
            withTitle: "Markdown Guide", action: #selector(AppDelegate.openMarkdownGuide(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Release Notes", action: #selector(AppDelegate.openReleaseNotes(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Report an Issue…", action: #selector(AppDelegate.reportIssue(_:)), keyEquivalent: "")
        NSApp.helpMenu = menu
        return menu
    }

    // MARK: Helpers

    private static func item(
        _ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func findItem(
        _ title: String, _ action: NSTextFinder.Action, _ key: String, _ modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
