import Testing
import Foundation
@testable import MocoCompanion

@Suite("APIRateGate", .timeLimit(.minutes(1)))
struct APIRateGateTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 0)
        func now() -> Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) {
            lock.withLock { value.addTimeInterval(seconds) }
        }
    }

    private actor Sleeper {
        private var pending: [CheckedContinuation<Void, any Error>] = []
        private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
        private(set) var delays: [TimeInterval] = []

        func sleep(_ seconds: TimeInterval) async throws {
            try await withCheckedThrowingContinuation { continuation in
                delays.append(seconds)
                pending.append(continuation)
                let ready = observers.filter { $0.0 <= delays.count }
                observers.removeAll { $0.0 <= delays.count }
                for (_, observer) in ready { observer.resume() }
            }
        }

        func waitForCalls(_ count: Int) async {
            if delays.count >= count { return }
            await withCheckedContinuation { observers.append((count, $0)) }
        }

        func wakeAll() {
            let waking = pending
            pending.removeAll()
            for continuation in waking { continuation.resume() }
        }
    }

    @Test("Concurrent waiters reserve separate windows and recheck after waking")
    func concurrentReservations() async throws {
        let clock = Clock()
        let sleeper = Sleeper()
        let gate = APIRateGate(limit: 1, windowSeconds: 60, safetyThreshold: 1,
                               now: { clock.now() }, sleep: { try await sleeper.sleep($0) })
        try await gate.waitForCapacity()
        let first = Task { try await gate.waitForCapacity() }
        let second = Task { try await gate.waitForCapacity() }
        await sleeper.waitForCalls(2)
        #expect(await gate.currentWindowCount == 1)
        #expect(await sleeper.delays == [60, 60])

        clock.advance(60)
        await sleeper.wakeAll()
        await sleeper.waitForCalls(3)
        #expect(await gate.currentWindowCount == 1)
        #expect(await sleeper.delays == [60, 60, 60])

        clock.advance(60)
        await sleeper.wakeAll()
        try await first.value
        try await second.value
        #expect(await gate.currentWindowCount == 1)
    }

    @Test("A waking waiter preserves an extended Retry-After deadline")
    func retryAfterExtension() async throws {
        let clock = Clock()
        let sleeper = Sleeper()
        let gate = APIRateGate(now: { clock.now() }, sleep: { try await sleeper.sleep($0) })
        await gate.recordRetryAfter(seconds: 10)
        let request = Task { try await gate.waitForCapacity() }
        await sleeper.waitForCalls(1)
        clock.advance(5)
        await gate.recordRetryAfter(seconds: 20)
        await gate.recordRetryAfter(seconds: 1) // Must not shorten the deadline.
        clock.advance(5)
        await sleeper.wakeAll()
        await sleeper.waitForCalls(2)
        #expect(await sleeper.delays == [10, 15])
        #expect(await gate.currentWindowCount == 0)
        clock.advance(15)
        await sleeper.wakeAll()
        try await request.value
        #expect(await gate.currentWindowCount == 1)
    }

    @Test("Cancellation after suspension does not reserve a slot")
    func cancellationDoesNotReserve() async throws {
        let clock = Clock()
        let sleeper = Sleeper()
        let gate = APIRateGate(now: { clock.now() }, sleep: { try await sleeper.sleep($0) })
        await gate.recordRetryAfter(seconds: 10)
        let request = Task { try await gate.waitForCapacity() }
        await sleeper.waitForCalls(1)
        request.cancel()
        clock.advance(10)
        await sleeper.wakeAll()
        do {
            try await request.value
            Issue.record("Cancelled request was admitted")
        } catch is CancellationError {
            // Expected even when the injected sleeper itself ignores cancellation.
        }
        #expect(await gate.currentWindowCount == 0)
    }

    @Test("Sleep cancellation propagates to the caller")
    func sleepCancellationPropagates() async {
        let gate = APIRateGate(sleep: { _ in throw CancellationError() })
        await gate.recordRetryAfter(seconds: 10)
        do {
            try await gate.waitForCapacity()
            Issue.record("Cancelled sleep was ignored")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await gate.currentWindowCount == 0)
    }
}
