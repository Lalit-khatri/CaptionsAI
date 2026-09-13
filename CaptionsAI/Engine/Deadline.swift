import Foundation

// MARK: - Deadline

/// Runs `operation`, but stops waiting for it after `seconds`.
///
/// This is deliberately not `Task.cancel()`. Cancellation in Swift is
/// cooperative: a task parked on a continuation that nobody ever resumes will
/// never notice it has been cancelled, and *awaiting* such a task hangs for
/// exactly as long as the thing being awaited does. That includes the implicit
/// await at the end of `withThrowingTaskGroup`, which is why the obvious
/// "race two child tasks" shape does not solve this problem.
///
/// So the operation is abandoned rather than stopped. It is cancelled as a
/// courtesy — anything that *does* honour cancellation should — but the caller
/// gets control back either way, and whatever the operation eventually
/// produces is dropped on the floor.
///
/// `sleep` is injected so tests can express a deadline without spending one.
func withDeadline<T>(
    seconds: TimeInterval,
    throwing timeoutError: @escaping () -> Error,
    sleep: @escaping (TimeInterval) async throws -> Void = {
        try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    },
    operation: @escaping () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let gate = ResumeOnce<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.arm(continuation)

            let work = Task {
                do {
                    let value = try await operation()
                    gate.finish(.success(value))
                } catch {
                    gate.finish(.failure(error))
                }
            }

            let timer = Task {
                try? await sleep(seconds)
                guard !Task.isCancelled else { return }
                work.cancel()
                gate.finish(.failure(timeoutError()))
            }

            gate.whenFinished {
                timer.cancel()
                work.cancel()
            }
        }
    } onCancel: {
        gate.finish(.failure(CancellationError()))
    }
}

// MARK: - ResumeOnce

/// A continuation that can be resumed from either of two racing tasks, and
/// resumes exactly once.
///
/// Resuming a `CheckedContinuation` twice is a crash, and the whole point of a
/// deadline is that two things are trying to finish the same call.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var finished = false
    private var onFinish: (() -> Void)?

    func arm(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if finished {
            let result = pendingResult
            lock.unlock()
            if let result {
                continuation.resume(with: result)
            }
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Runs `block` when the call completes, or immediately if it already has.
    func whenFinished(_ block: @escaping () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            block()
            return
        }
        onFinish = block
        lock.unlock()
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        pendingResult = result
        let cont = continuation
        continuation = nil
        let block = onFinish
        onFinish = nil
        lock.unlock()

        cont?.resume(with: result)
        block?()
    }
}
