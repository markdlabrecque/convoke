import XCTest

/// A test-only, main-actor event gate. Signals are retained as a revision, not polled.
/// Predicates are checked after the signaling task yields the actor, so assertions
/// observe the controller's processing, not just the fake's incoming callback.
@MainActor
final class AsyncTestGate {
    struct Failure: Error, Equatable, CustomStringConvertible {
        let description: String
    }
    private(set) var revision = 0
    private var waiters: [UUID: (CheckedContinuation<Void, Error>, Task<Void, Never>)] = [:]
    var waiterCount: Int { waiters.count }
    var onWait: (() -> Void)?

    func signal() {
        revision += 1
        for id in Array(waiters.keys) { resolve(id, error: nil) }
    }

    func expire() {
        for id in Array(waiters.keys) {
            resolve(id, error: Failure(description: "Expired test milestone"))
        }
    }

    private func resolve(_ id: UUID, error: Error?) {
        guard let (continuation, watchdog) = waiters.removeValue(forKey: id) else { return }
        watchdog.cancel()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func wait(after observed: Int, named milestone: String, timeout: UInt64 = 5_000_000_000) async throws {
        guard !Task.isCancelled else { throw Failure(description: "Cancelled waiting for \(milestone)") }
        if revision > observed { return }
        let id = UUID()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let watchdog = Task { @MainActor [weak self] in
                        do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                        self?.resolve(id, error: Failure(description: "Timed out waiting for \(milestone)"))
                    }
                    waiters[id] = (continuation, watchdog)
                    onWait?()
                }
            } onCancel: {
                Task { @MainActor in self.resolve(id, error: CancellationError()) }
            }
        } catch is CancellationError {
            throw Failure(description: "Cancelled waiting for \(milestone)")
        } catch {
            throw Failure(description: "\(milestone): \(error)")
        }
    }

    /// Each iteration suspends on a fake event; there is no scheduling/state polling.
    /// One deadline covers the whole wait, even if unrelated events keep arriving.
    func wait(until predicate: () -> Bool, named milestone: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !predicate() {
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { throw Failure(description: "Timed out waiting for \(milestone)") }
            let parts = remaining.components
            let nanoseconds = UInt64(parts.seconds) * 1_000_000_000 + UInt64(parts.attoseconds / 1_000_000_000)
            let observed = revision
            try await wait(after: observed, named: milestone, timeout: nanoseconds)
        }
    }

    /// Unstructured controller tasks may deliberately ignore cancellation in a fake.
    /// Never turn a failed milestone into an unbounded task.value in the test itself.
    static func join(_ task: Task<Void, Never>, named milestone: String, timeout: UInt64 = 5_000_000_000) async throws {
        let completed = AsyncTestGate()
        let observer = Task { @MainActor in
            await task.value
            completed.signal()
        }
        defer { observer.cancel() }
        do { try await completed.wait(after: 0, named: milestone, timeout: timeout) }
        catch { task.cancel(); throw error }
    }
}

@MainActor
final class AsyncTestGateTests: XCTestCase {
    func testEarlySignalAndNormalDeliveryResumeOnce() async throws {
        let gate = AsyncTestGate()
        gate.signal()
        try await gate.wait(after: 0, named: "early audio")
        gate.onWait = { gate.signal() }
        try await gate.wait(after: 1, named: "next audio")
        gate.onWait = nil
        gate.signal()
        XCTAssertEqual(gate.waiterCount, 0)
    }

    func testWatchdogExpiryNamesMilestoneAndCleansUp() async {
        let gate = AsyncTestGate()
        do {
            try await gate.wait(after: 0, named: "missing audio", timeout: 0)
            XCTFail("Expected watchdog error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("missing audio"))
            XCTAssertTrue(String(describing: error).contains("Timed out"))
        }
        XCTAssertEqual(gate.waiterCount, 0)
        gate.signal()
    }

    func testFailedJoinCancelsTaskWithoutUnboundedCleanup() async throws {
        let worker = AsyncTestGate()
        let finished = AsyncTestGate()
        let task = Task {
            do { try await worker.wait(after: 0, named: "worker held") } catch {}
            finished.signal()
        }
        do {
            try await AsyncTestGate.join(task, named: "controller task returned", timeout: 0)
            XCTFail("Expected join watchdog")
        } catch {
            XCTAssertTrue(String(describing: error).contains("controller task returned"))
        }
        XCTAssertTrue(task.isCancelled)
        try await finished.wait(after: 0, named: "cancelled worker cleaned up")
        XCTAssertEqual(worker.waiterCount, 0)
    }

    func testExpirationAndCancellationCleanUpAndNameMilestone() async {
        for cancel in [false, true] {
            let gate = AsyncTestGate()
            let registered = expectation(description: "waiter registered")
            gate.onWait = { registered.fulfill() }
            let task = Task { try await gate.wait(after: 0, named: "held EOF") }
            await fulfillment(of: [registered], timeout: 2)
            if cancel { task.cancel() } else { gate.expire() }
            do { try await task.value; XCTFail("Expected named failure") }
            catch { XCTAssertTrue(String(describing: error).contains("held EOF")) }
            XCTAssertEqual(gate.waiterCount, 0)
            gate.onWait = nil
            gate.signal() // A late signal must not resume the removed continuation again.
        }
    }
}
