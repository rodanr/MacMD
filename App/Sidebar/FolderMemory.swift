import Observation

/// The folders open in the Files sidebar, shared by every document: opening a file elsewhere, in another tab or
/// under another root never closes the folders you opened. Paths are `FileNavigation.realPath`s, so they hold
/// under any root. Kept for the app session.
@MainActor @Observable
final class FolderMemory {
    static let shared = FolderMemory()

    var expanded: Set<String> = []
}
