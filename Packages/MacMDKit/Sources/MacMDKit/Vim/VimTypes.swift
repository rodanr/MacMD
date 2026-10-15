import Foundation

/// A key press as the Vim engine sees it.
public enum VimKey: Equatable, Sendable {
    case char(Character)
    case ctrl(Character)
    case escape, enter, backspace, tab
    case left, right, up, down
}

public enum VimMode: Equatable, Sendable {
    case normal, insert, visual, visualLine
    /// Typing an Ex command (`:`) or a search (`/`, `?`).
    case commandLine(prompt: Character, text: String)
}

/// What the editor should do in response to a key. Actions are applied in order.
public enum VimAction: Equatable, Sendable {
    /// Handle the key as ordinary typing (insert mode).
    case passThrough
    /// Replace a range of the document as one undoable edit.
    case replace(NSRange, with: String)
    /// Set the selection; a zero length places the cursor.
    case select(NSRange)
    /// Move the cursor by display lines, which only the editor's layout knows. The editor reports
    /// the new position back through `VimEngine.cursorMoved(to:text:)`.
    case moveDisplayLines(Int)
    case scrollHalfPage(down: Bool)
    case centerCursor
    case undo, redo
    case save, close
    /// Feed these keys back through the engine (the `.` command).
    case replay([VimKey])
    case beep
}
