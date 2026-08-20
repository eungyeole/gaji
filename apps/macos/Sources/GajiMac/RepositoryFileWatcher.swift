import CoreServices
import Foundation

final class RepositoryFileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable (Bool) -> Void

    init(path: String, onChange: @escaping @Sendable (Bool) -> Void) {
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
                let relevant = values.prefix(count).filter {
                    !$0.contains("/target/") &&
                    !$0.contains("/.build/") &&
                    !$0.contains("/node_modules/") &&
                    !$0.contains("/docs/dist/")
                }
                guard !relevant.isEmpty else { return }
                watcher.onChange(relevant.contains { $0.contains("/.git/") })
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

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
