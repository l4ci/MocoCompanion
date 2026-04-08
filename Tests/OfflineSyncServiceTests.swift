import Testing
import Foundation

@Suite("OfflineSyncService")
struct OfflineSyncServiceTests {

    // MARK: - Helpers

    @MainActor
    private func makeService(client: MockMocoClient = MockMocoClient()) -> (OfflineSyncService, MockMocoClient) {
        let capturedClient = client
        let service = OfflineSyncService(clientFactory: { capturedClient })
        return (service, capturedClient)
    }

    @MainActor
    private func makeQueue(entries: [(projectId: Int, taskId: Int, description: String)] = []) -> EntryQueue {
        let queue = EntryQueue(backend: InMemoryBackend())
        for entry in entries {
            queue.enqueue(
                date: "2026-04-01",
                projectId: entry.projectId, taskId: entry.taskId,
                projectName: "P", taskName: "T",
                description: entry.description,
                seconds: 3600, tag: nil
            )
        }
        return queue
    }

    // MARK: - Empty queue

    @Test("sync does nothing when queue is empty")
    @MainActor func syncEmptyQueue() async {
        var client = MockMocoClient()
        var fetchCalled = false
        client.fetchActivitiesHandler = { _, _, _ in fetchCalled = true; return [] }

        let (service, _) = makeService(client: client)
        let queue = makeQueue()

        var callbackFired = false
        await service.sync(queue: queue, userId: 42) { _ in callbackFired = true }

        #expect(!fetchCalled)
        #expect(!callbackFired)
    }

    // MARK: - No client

    @Test("sync does nothing when client factory returns nil")
    @MainActor func syncNilClient() async {
        let service = OfflineSyncService(clientFactory: { nil })
        let queue = makeQueue(entries: [(100, 200, "Standup")])

        var callbackFired = false
        await service.sync(queue: queue, userId: 42) { _ in callbackFired = true }

        #expect(queue.count == 1)
        #expect(!callbackFired)
    }

    // MARK: - Dedup: skip duplicate entry

    @Test("sync skips entry that already exists on the server")
    @MainActor func syncSkipsDuplicate() async {
        let existing = TestFactories.makeActivity(
            id: 99, projectId: 100, taskId: 200, description: "Standup"
        )
        var client = MockMocoClient()
        client.fetchActivitiesHandler = { _, _, _ in [existing] }

        var createCalled = false
        client.createActivityHandler = { _, _, _, _, _, _ in
            createCalled = true
            return existing
        }

        let (service, _) = makeService(client: client)
        let queue = makeQueue(entries: [(100, 200, "Standup")])

        var syncedCount = 0
        await service.sync(queue: queue, userId: 42) { count in syncedCount = count }

        #expect(!createCalled, "Should not create a duplicate activity")
        #expect(syncedCount == 0)
        #expect(queue.isEmpty, "Duplicate entry should be removed from the queue")
    }

    // MARK: - Happy path: create non-duplicate

    @Test("sync creates entry that does not exist on the server")
    @MainActor func syncCreatesNewEntry() async {
        var client = MockMocoClient()
        client.fetchActivitiesHandler = { _, _, _ in [] }  // no existing activities

        let created = TestFactories.makeActivity(id: 1, projectId: 100, taskId: 200, description: "Code review")
        var createCallCount = 0
        client.createActivityHandler = { date, projectId, taskId, desc, seconds, tag in
            createCallCount += 1
            return created
        }

        let (service, _) = makeService(client: client)
        let queue = makeQueue(entries: [(100, 200, "Code review")])

        var syncedCount = 0
        await service.sync(queue: queue, userId: 42) { count in syncedCount = count }

        #expect(createCallCount == 1)
        #expect(syncedCount == 1)
        #expect(queue.isEmpty)
    }

    // MARK: - Mixed: one dup, one new

    @Test("sync skips duplicate and creates non-duplicate in same batch")
    @MainActor func syncMixedBatch() async {
        let existing = TestFactories.makeActivity(
            id: 10, projectId: 100, taskId: 200, description: "Standup"
        )
        var client = MockMocoClient()
        client.fetchActivitiesHandler = { _, _, _ in [existing] }

        let newActivity = TestFactories.makeActivity(id: 11, projectId: 300, taskId: 400, description: "Code review")
        var createdDescriptions: [String] = []
        client.createActivityHandler = { _, _, _, desc, _, _ in
            createdDescriptions.append(desc)
            return newActivity
        }

        let (service, _) = makeService(client: client)
        let queue = makeQueue(entries: [
            (100, 200, "Standup"),     // duplicate
            (300, 400, "Code review")  // new
        ])

        var syncedCount = 0
        await service.sync(queue: queue, userId: 42) { count in syncedCount = count }

        #expect(createdDescriptions == ["Code review"])
        #expect(syncedCount == 1)
        #expect(queue.isEmpty)
    }

    // MARK: - API error stops batch

    @Test("sync stops after first API error and leaves remaining entries in queue")
    @MainActor func syncStopsOnError() async {
        var client = MockMocoClient()
        client.fetchActivitiesHandler = { _, _, _ in
            throw MocoError.serverError(statusCode: 500, message: "Internal error")
        }

        let (service, _) = makeService(client: client)
        let queue = makeQueue(entries: [
            (100, 200, "Entry A"),
            (300, 400, "Entry B")
        ])

        var callbackFired = false
        await service.sync(queue: queue, userId: 42) { _ in callbackFired = true }

        #expect(!callbackFired)
        #expect(queue.count == 2, "Queue should be unchanged after error")
    }
}
