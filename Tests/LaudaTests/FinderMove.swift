import Foundation

/// A file moved as the Finder moves it: under a file coordinator, which is
/// what tells an open document about it (a bare move does not).
enum FinderMove {
    /// Off the main thread, and awaited: the coordinator waits for the
    /// document to answer, and a document with something to save answers on
    /// the main thread. Coordinating there stopped the tests now and then,
    /// each side waiting for the other (sampled: the main thread in
    /// `coordinate`, never returning).
    static func move(_ from: URL, to target: URL) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var coordinationError: NSError?
                var moveError: Error?
                let coordinator = NSFileCoordinator(filePresenter: nil)
                coordinator.coordinate(
                    writingItemAt: from, options: .forMoving,
                    writingItemAt: target, options: .forReplacing, error: &coordinationError
                ) { source, destination in
                    do {
                        try FileManager.default.moveItem(at: source, to: destination)
                        coordinator.item(at: source, didMoveTo: destination)
                    } catch {
                        moveError = error
                    }
                }
                if let error = coordinationError ?? moveError {
                    done.resume(throwing: error)
                } else {
                    done.resume()
                }
            }
        }
    }
}
