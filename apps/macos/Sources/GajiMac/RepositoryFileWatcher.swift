import CoreServices
import Foundation

final class RepositoryFileWatcher: @unchecked Sendable {
    struct Change: OptionSet, Sendable {
        let rawValue: UInt8
        static let workingCopy = Change(rawValue: 1 << 0)
        static let metadata = Change(rawValue: 1 << 1)
    }

    private var stream: FSEventStreamRef?
    private let onChange: @Sendable (Change) -> Void

    init(path: String, onChange: @escaping @Sendable (Change) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<RepositoryFileWatcher>.fromOpaque(info).takeUnretainedValue()
                let values = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                let change = values.prefix(count).reduce(into: Change()) { change, path in
                    change.formUnion(RepositoryFileWatcher.classify(path))
                }
                guard !change.isEmpty else { return }
                watcher.onChange(change)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }

    private static func classify(_ path: String) -> Change {
        if path.contains("/target/") || path.contains("/.build/") ||
            path.contains("/node_modules/") || path.contains("/docs/dist/") {
            return []
        }
        guard let gitRange = path.range(of: "/.git/") else { return .workingCopy }
        let gitPath = String(path[gitRange.upperBound...])
        if gitPath == "index" || gitPath == "index.lock" { return .workingCopy }
        if gitPath == "HEAD" || gitPath == "ORIG_HEAD" || gitPath == "packed-refs" ||
            gitPath.hasPrefix("refs/") || gitPath.hasPrefix("rebase-") ||
            gitPath.hasPrefix("sequencer/") || gitPath.hasSuffix("_HEAD") {
            return [.workingCopy, .metadata]
        }
        return []
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
