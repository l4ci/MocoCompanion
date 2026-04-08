import Testing
import Foundation

@Suite("SessionManager")
struct SessionManagerTests {

    // MARK: - Helpers

    @MainActor
    private func makeManager() -> (SessionManager, ValueBox<Int?>) {
        let userIdBox = ValueBox<Int?>(nil)
        let manager = SessionManager(userIdBox: userIdBox)
        return (manager, userIdBox)
    }

    // MARK: - fetchSession sets userId

    @Test("fetchSession sets currentUserId and updates userIdBox")
    @MainActor func fetchSessionSetsUserId() async {
        var client = MockMocoClient()
        client.fetchSessionHandler = {
            let json: [String: Any] = ["id": 42, "uuid": "test-uuid"]
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! JSONDecoder().decode(MocoSession.self, from: data)
        }
        client.fetchUserProfileHandler = { userId in
            let json: [String: Any] = ["id": userId, "firstname": "Jane", "lastname": "Doe"]
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! JSONDecoder().decode(MocoUserProfile.self, from: data)
        }

        let (manager, userIdBox) = makeManager()
        #expect(manager.currentUserId == nil)

        await manager.fetchSession(client: client)

        #expect(manager.currentUserId == 42)
        #expect(userIdBox.value == 42)
    }

    // MARK: - fetchSession sets profile

    @Test("fetchSession populates currentUserProfile with name")
    @MainActor func fetchSessionSetsProfile() async {
        var client = MockMocoClient()
        client.fetchSessionHandler = {
            let json: [String: Any] = ["id": 42, "uuid": "test-uuid"]
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! JSONDecoder().decode(MocoSession.self, from: data)
        }
        client.fetchUserProfileHandler = { userId in
            let json: [String: Any] = ["id": userId, "firstname": "Jane", "lastname": "Doe"]
            let data = try! JSONSerialization.data(withJSONObject: json)
            return try! JSONDecoder().decode(MocoUserProfile.self, from: data)
        }

        let (manager, _) = makeManager()
        await manager.fetchSession(client: client)

        #expect(manager.currentUserProfile != nil)
        #expect(manager.currentUserProfile?.firstname == "Jane")
        #expect(manager.currentUserProfile?.lastname == "Doe")
    }

    // MARK: - nil client handling

    @Test("fetchSession with nil client does nothing")
    @MainActor func fetchSessionNilClient() async {
        let (manager, userIdBox) = makeManager()

        await manager.fetchSession(client: nil)

        #expect(manager.currentUserId == nil)
        #expect(manager.currentUserProfile == nil)
        #expect(userIdBox.value == nil)
    }

    // MARK: - fetchSession error handling

    @Test("fetchSession handles API error gracefully without crashing")
    @MainActor func fetchSessionError() async {
        var client = MockMocoClient()
        client.fetchSessionHandler = {
            throw MocoError.serverError(statusCode: 401, message: "Unauthorized")
        }

        let (manager, _) = makeManager()
        await manager.fetchSession(client: client)

        #expect(manager.currentUserId == nil)
        #expect(manager.currentUserProfile == nil)
    }

    // MARK: - syncQueuedEntries

    @Test("syncQueuedEntries skips when queue is empty")
    @MainActor func syncSkipsEmptyQueue() async {
        var client = MockMocoClient()
        var fetchCalled = false
        client.fetchActivitiesHandler = { _, _, _ in
            fetchCalled = true
            return []
        }

        let (manager, _) = makeManager()
        let queue = EntryQueue(backend: InMemoryBackend())
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        await manager.syncQueuedEntries(
            queue: queue,
            client: client,
            userId: 42,
            dispatcher: dispatcher,
            onSynced: {}
        )

        #expect(!fetchCalled)
    }

    @Test("syncQueuedEntries skips when client is nil")
    @MainActor func syncSkipsNilClient() async {
        let (manager, _) = makeManager()
        let queue = EntryQueue(backend: InMemoryBackend())
        queue.enqueue(
            date: "2026-04-01", projectId: 100, taskId: 200,
            projectName: "P", taskName: "T",
            description: "test", seconds: 3600, tag: nil
        )
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        await manager.syncQueuedEntries(
            queue: queue,
            client: nil,
            userId: 42,
            dispatcher: dispatcher,
            onSynced: {}
        )

        // Queue should remain unchanged
        #expect(queue.count == 1)
    }

    @Test("syncQueuedEntries with nil userId skips sync")
    @MainActor func syncSkipsNilUserId() async {
        let client = MockMocoClient()
        let (manager, _) = makeManager()
        let queue = EntryQueue(backend: InMemoryBackend())
        queue.enqueue(
            date: "2026-04-01", projectId: 100, taskId: 200,
            projectName: "P", taskName: "T",
            description: "test", seconds: 3600, tag: nil
        )
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        await manager.syncQueuedEntries(
            queue: queue,
            client: client,
            userId: nil,
            dispatcher: dispatcher,
            onSynced: {}
        )

        #expect(queue.count == 1)
    }
}
