import CoreServices
import Foundation

struct FileSystemChange: Sendable {
    let path: String
    let flags: UInt32

    var isDirectory: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
    }

    var wasCreated: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
    }

    var wasRemoved: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }

    var wasRenamed: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
    }
}

final class FileSystemEventMonitor {
    typealias Handler = @Sendable ([FileSystemChange], Bool) -> Void

    private let queue = DispatchQueue(label: "QuickFiles.FileEvents", qos: .utility)
    private var stream: FSEventStreamRef?
    private var handler: Handler?
    private var pendingFlagsByPath: [String: UInt32] = [:]
    private var pendingFullRescan = false
    private var deliveryWorkItem: DispatchWorkItem?

    func start(folders: [URL], handler: @escaping Handler) {
        let paths = folders
            .map { $0.standardizedFileURL.path }
            .filter { !$0.isEmpty }

        queue.sync {
            stopOnQueue()
            self.handler = handler
            guard !paths.isEmpty else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot
            )

            guard let stream = FSEventStreamCreate(
                nil,
                Self.eventCallback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.35,
                flags
            ) else { return }

            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return
            }
            self.stream = stream
        }
    }

    func flush() {
        queue.async { [weak self] in
            guard let stream = self?.stream else { return }
            FSEventStreamFlushAsync(stream)
        }
    }

    func stop() {
        queue.sync {
            stopOnQueue()
            handler = nil
        }
    }

    private func stopOnQueue() {
        deliveryWorkItem?.cancel()
        deliveryWorkItem = nil
        pendingFlagsByPath.removeAll(keepingCapacity: true)
        pendingFullRescan = false

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func receive(paths: NSArray, flags: UnsafePointer<FSEventStreamEventFlags>, count: Int) {
        let fullRescanFlags = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagMount |
            kFSEventStreamEventFlagUnmount
        )

        for index in 0..<count {
            guard let path = paths[index] as? String else { continue }
            let eventFlags = UInt32(flags[index])
            pendingFlagsByPath[path, default: 0] |= eventFlags
            if eventFlags & fullRescanFlags != 0 {
                pendingFullRescan = true
            }
        }

        scheduleDelivery()
    }

    private func scheduleDelivery() {
        deliveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changes = pendingFlagsByPath.map { FileSystemChange(path: $0.key, flags: $0.value) }
            let needsFullRescan = pendingFullRescan
            pendingFlagsByPath.removeAll(keepingCapacity: true)
            pendingFullRescan = false
            deliveryWorkItem = nil
            handler?(changes, needsFullRescan)
        }
        deliveryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private static let eventCallback: FSEventStreamCallback = {
        _, clientInfo, eventCount, eventPaths, eventFlags, _ in
        guard let clientInfo else { return }
        let monitor = Unmanaged<FileSystemEventMonitor>.fromOpaque(clientInfo).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        monitor.receive(paths: paths, flags: eventFlags, count: eventCount)
    }

    deinit {
        stop()
    }
}
