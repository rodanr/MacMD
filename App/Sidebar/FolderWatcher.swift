import CoreServices
import Foundation
import MacMDKit

/// Reports which folders below a folder changed, through FSEvents, the same service Finder relies on. It sees
/// changes from every app (Finder, git, the terminal), coalesced over a short delay. Events are per folder
/// (a file added, removed or renamed in it), never per write, so busy folders stay cheap.
@MainActor
final class FolderWatcher {
    /// The changed folders (`FileNavigation.realPath` form), or nil when everything below must be re-read
    /// (FSEvents dropped events).
    typealias Handler = @MainActor (Set<String>?) -> Void

    /// Handed to the C callback; retained by the stream until the watcher goes away.
    private final class Box {
        let onChange: Handler
        init(_ onChange: @escaping Handler) { self.onChange = onChange }
    }

    private nonisolated(unsafe) let stream: FSEventStreamRef?

    init(folder: URL, latency: TimeInterval = 0.3, onChange: @escaping Handler) {
        let box = Unmanaged.passRetained(Box(onChange))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(), retain: nil,
            release: { info in info.map { Unmanaged<Box>.fromOpaque($0).release() } }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            let rescan = (0..<count).contains { index in
                flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
            }
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let folders = Set(changed.map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
            // The stream delivers on the main queue (below).
            MainActor.assumeIsolated { box.onChange(rescan ? nil : folders) }
        }
        // FSEvents reports real paths, so watch the real one.
        stream = FSEventStreamCreate(
            nil, callback, &context, [FileNavigation.realPath(folder)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        // Without a stream nothing will release the box; a tiny leak beats guessing FSEvents' cleanup.
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    // Stopping is safe from any thread; events already queued only reach the box, never a freed watcher.
    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)  // releases the box through the context's release callback
    }
}
