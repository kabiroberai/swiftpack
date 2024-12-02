import Foundation

extension Process {
    /// Suspends until the receiver is finished.
    ///
    /// - Parameter onCancel: The action to take if the current
    /// task is cancelled.
    public func waitForExit(onCancel: TaskCancelAction = .interrupt) async {
        await withTaskCancellationHandler {
            let oldHandler = terminationHandler
            await withCheckedContinuation { continuation in
                terminationHandler = {
                    oldHandler?($0)
                    continuation.resume()
                }
            }
        } onCancel: {
            switch onCancel {
            case .interrupt:
                interrupt()
            case .terminate:
                terminate()
            case .ignore:
                break
            }
        }
    }

    public enum TaskCancelAction: Sendable {
        /// Sends `SIGINT` to the process.
        case interrupt
        /// Sends `SIGTERM` to the process.
        case terminate
        /// Don't participate in cooperative cancellation.
        case ignore
    }
}

struct TemporaryDirectory: ~Copyable {
    private var shouldDelete = true

    let url: URL

    init(name: String) throws {
        self.url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        _delete()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func _delete() {
        try? FileManager.default.removeItem(at: url)
    }

    consuming func persist() -> URL {
        shouldDelete = false
        return url
    }

    consuming func persist(at location: URL) throws {
        try FileManager.default.moveItem(at: url, to: location)
        // we do this after moving, so that if the move fails we clean up
        shouldDelete = false
    }

    deinit {
        if shouldDelete { _delete() }
    }
}

extension Data {
    // AsyncBytes is Darwin-only :/

    init(reading fileHandle: FileHandle) async throws {
        #if canImport(Darwin)
        self = try await fileHandle.bytes.reduce(into: Data()) { $0.append($1) }
        #else
        self = try fileHandle.readToEnd() ?? Data()
        #endif
    }

    init(reading file: URL) async throws {
        #if canImport(Darwin)
        self = try await file.resourceBytes.reduce(into: Data()) { $0.append($1) }
        #else
        try self.init(contentsOf: file)
        #endif
    }
}
