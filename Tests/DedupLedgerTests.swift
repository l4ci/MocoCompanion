import Testing
import Foundation

@Suite("DedupLedger")
struct DedupLedgerTests {

    private func makeAlert(
        key: String = "test:alert",
        strategy: MonitorAlert.DedupStrategy = .once
    ) -> MonitorAlert {
        MonitorAlert(
            type: .idleReminder,
            message: "test",
            dedupKey: key,
            dedupStrategy: strategy
        )
    }

    // MARK: - Once Strategy

    @Test("Once: fires on first check")
    func onceFirstFire() {
        let ledger = DedupLedger()
        let alert = makeAlert(strategy: .once)
        #expect(ledger.shouldFire(alert))
    }

    @Test("Once: does not fire after marking")
    func onceAfterMark() {
        var ledger = DedupLedger()
        let alert = makeAlert(strategy: .once)
        ledger.markFired(alert)
        #expect(!ledger.shouldFire(alert))
    }

    @Test("Once: different keys are independent")
    func onceIndependentKeys() {
        var ledger = DedupLedger()
        let a = makeAlert(key: "monitor:a", strategy: .once)
        let b = makeAlert(key: "monitor:b", strategy: .once)
        ledger.markFired(a)
        #expect(!ledger.shouldFire(a))
        #expect(ledger.shouldFire(b))
    }

    // MARK: - Rate Limited Strategy

    @Test("Rate limited: fires when interval has passed")
    func rateLimitedFires() {
        var ledger = DedupLedger()
        let alert = makeAlert(strategy: .rateLimited(60))
        let past = Date().addingTimeInterval(-120) // 2 min ago
        ledger.markFired(alert, at: past)
        #expect(ledger.shouldFire(alert, now: Date()))
    }

    @Test("Rate limited: blocks within interval")
    func rateLimitedBlocks() {
        var ledger = DedupLedger()
        let alert = makeAlert(strategy: .rateLimited(60))
        let recent = Date().addingTimeInterval(-30) // 30s ago
        ledger.markFired(alert, at: recent)
        #expect(!ledger.shouldFire(alert, now: Date()))
    }

    @Test("Rate limited: fires on first check (no history)")
    func rateLimitedFirstCheck() {
        let ledger = DedupLedger()
        let alert = makeAlert(strategy: .rateLimited(60))
        #expect(ledger.shouldFire(alert))
    }

    // MARK: - Per Day Strategy

    @Test("Per day: fires on first check")
    func perDayFirstCheck() {
        let ledger = DedupLedger()
        let alert = makeAlert(strategy: .perDay)
        #expect(ledger.shouldFire(alert))
    }

    @Test("Per day: blocks on same day")
    func perDayBlocksSameDay() {
        var ledger = DedupLedger()
        let alert = makeAlert(strategy: .perDay)
        ledger.markFired(alert)
        #expect(!ledger.shouldFire(alert))
    }

    @Test("Per day: fires on next day")
    func perDayFiresNextDay() {
        var ledger = DedupLedger()
        let alert = makeAlert(strategy: .perDay)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ledger.markFired(alert, at: yesterday)
        #expect(ledger.shouldFire(alert, now: Date()))
    }

    // MARK: - Clear

    @Test("Clear prefix removes matching entries")
    func clearPrefix() {
        var ledger = DedupLedger()
        let a = makeAlert(key: "Monitor:idle", strategy: .once)
        let b = makeAlert(key: "Monitor:forgotten", strategy: .once)
        let c = makeAlert(key: "Other:alert", strategy: .once)
        ledger.markFired(a)
        ledger.markFired(b)
        ledger.markFired(c)

        ledger.clearPrefix("Monitor:")

        #expect(ledger.shouldFire(a)) // cleared
        #expect(ledger.shouldFire(b)) // cleared
        #expect(!ledger.shouldFire(c)) // not cleared — different prefix
    }

    @Test("Clear all removes everything")
    func clearAll() {
        var ledger = DedupLedger()
        let a = makeAlert(key: "x:a", strategy: .once)
        let b = makeAlert(key: "y:b", strategy: .once)
        ledger.markFired(a)
        ledger.markFired(b)

        ledger.clearAll()

        #expect(ledger.shouldFire(a))
        #expect(ledger.shouldFire(b))
    }
}
