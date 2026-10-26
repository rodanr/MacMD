import MacMDKit
import Observation

/// The folders open in the Files sidebar, shared by every document: opening a file elsewhere, in another tab or
/// under another root never closes the folders you opened. Paths are `FileNavigation.realPath`s, so they hold
/// under any root. Kept for the app session.
@MainActor @Observable
final class FolderMemory {
    static let shared = FolderMemory()

    var expanded: Set<String> = []

    /// What a document last learned about a browsed folder, so the next document in it starts with the same
    /// list instead of an unordered one that reshuffles when the scan finishes.
    struct Snapshot {
        let tree: FileNode
        var index: MarkdownIndex?
    }

    @ObservationIgnored private var snapshots: [String: Snapshot] = [:]

    func snapshot(for folderPath: String) -> Snapshot? { snapshots[folderPath] }

    func store(index: MarkdownIndex?, tree: FileNode) {
        snapshots[tree.path] = Snapshot(tree: tree, index: index)
    }
}
