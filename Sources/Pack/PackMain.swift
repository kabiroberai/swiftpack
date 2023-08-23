import Foundation
import ArgumentParser

@main struct Main {
    static func main() async throws {
        let (canStart, cont) = AsyncStream.makeStream(of: Never.self)
        let task = Task {
            for await _ in canStart {}
            guard !Task.isCancelled else { return }
            do {
                var command = try PackCommand.parseAsRoot()
                if var asyncCommand = command as? AsyncParsableCommand {
                    try await asyncCommand.run()
                } else {
                    try command.run()
                }
            } catch is CancellationError {
                PackCommand.exit()
            } catch {
                PackCommand.exit(withError: error)
            }
        }

        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT)
        source.setEventHandler { task.cancel() }
        source.resume()

        cont.finish()

        await task.value
    }
}
