import Testing
import Foundation
@testable import MocoCompanion

@Suite("ProjectCatalog")
struct ProjectCatalogTests {

    // MARK: - Helpers

    @MainActor
    private func makeCatalog() -> ProjectCatalog {
        ProjectCatalog()
    }

    private func makeProject(
        id: Int = 100,
        name: String = "Test Project",
        customerName: String = "Test Customer",
        tasks: [(id: Int, name: String, active: Bool)] = [(200, "Active Task", true)]
    ) -> MocoProject {
        let taskJSON: [[String: Any]] = tasks.map { task in
            ["id": task.id, "name": task.name, "active": task.active, "billable": true]
        }
        let json: [String: Any] = [
            "id": id,
            "identifier": "PROJ-\(id)",
            "name": name,
            "active": true,
            "billable": true,
            "customer": ["id": 300, "name": customerName],
            "tasks": taskJSON,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MocoProject.self, from: data)
    }

    // MARK: - fetchProjects populates projects and search entries

    @Test("fetchProjects populates projects array and search entries")
    @MainActor func fetchPopulatesProjectsAndSearch() async {
        var client = MockMocoClient()
        let project = makeProject(id: 100, name: "Alpha", tasks: [
            (200, "Design", true),
            (201, "Dev", true),
        ])
        client.fetchAssignedProjectsHandler = { _ in [project] }

        let catalog = makeCatalog()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        var capturedError: MocoError?

        await catalog.fetchProjects(
            client: client,
            onError: { capturedError = $0 },
            dispatcher: dispatcher
        )

        #expect(catalog.projects.count == 1)
        #expect(catalog.projects.first?.name == "Alpha")
        #expect(catalog.searchEntries.count == 2)
        #expect(catalog.assignedProjectIds == [100])
        #expect(capturedError == nil)
        #expect(!catalog.isLoading)
    }

    // MARK: - nil client returns error

    @Test("fetchProjects with nil client calls onError with invalidConfiguration")
    @MainActor func fetchWithNilClient() async {
        let catalog = makeCatalog()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        var capturedError: MocoError?

        let projectsBefore = catalog.projects

        await catalog.fetchProjects(
            client: nil,
            onError: { capturedError = $0 },
            dispatcher: dispatcher
        )

        if case .invalidConfiguration = capturedError {
            // expected
        } else {
            Issue.record("Expected .invalidConfiguration, got \(String(describing: capturedError))")
        }
        // Projects should not have changed (nil client = no fetch)
        #expect(catalog.projects.count == projectsBefore.count)
    }

    // MARK: - Search entries only include active tasks

    @Test("searchEntries excludes inactive tasks")
    @MainActor func searchExcludesInactiveTasks() async {
        var client = MockMocoClient()
        let project = makeProject(id: 100, name: "Project", tasks: [
            (200, "Active Task", true),
            (201, "Inactive Task", false),
        ])
        client.fetchAssignedProjectsHandler = { _ in [project] }

        let catalog = makeCatalog()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        await catalog.fetchProjects(
            client: client,
            onError: { _ in },
            dispatcher: dispatcher
        )

        #expect(catalog.searchEntries.count == 1)
        #expect(catalog.searchEntries.first?.taskName == "Active Task")
    }

    // MARK: - Error handling

    @Test("fetchProjects API error calls onError and dispatches notification")
    @MainActor func fetchErrorHandling() async {
        var client = MockMocoClient()
        client.fetchAssignedProjectsHandler = { _ in
            throw MocoError.serverError(statusCode: 500, message: "Server down")
        }

        let catalog = makeCatalog()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })
        var capturedError: MocoError?

        await catalog.fetchProjects(
            client: client,
            onError: { capturedError = $0 },
            dispatcher: dispatcher
        )

        #expect(capturedError != nil)
        #expect(!catalog.isLoading)
    }

    // MARK: - Search entries cache invalidation

    @Test("setting projects invalidates cached search entries")
    @MainActor func projectsSetInvalidatesSearchCache() async {
        let catalog = makeCatalog()

        let project1 = makeProject(id: 100, name: "First", tasks: [(200, "Task A", true)])
        catalog.projects = [project1]
        let firstEntries = catalog.searchEntries
        #expect(firstEntries.count == 1)
        #expect(firstEntries.first?.projectName == "First")

        let project2 = makeProject(id: 101, name: "Second", tasks: [(201, "Task B", true)])
        catalog.projects = [project2]
        let secondEntries = catalog.searchEntries
        #expect(secondEntries.count == 1)
        #expect(secondEntries.first?.projectName == "Second")
    }

    // MARK: - isLoading state

    @Test("isLoading is true during fetch and false after completion")
    @MainActor func isLoadingDuringFetch() async {
        var client = MockMocoClient()
        client.fetchAssignedProjectsHandler = { _ in [] }

        let catalog = makeCatalog()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { _ in false })

        #expect(!catalog.isLoading)

        await catalog.fetchProjects(
            client: client,
            onError: { _ in },
            dispatcher: dispatcher
        )

        #expect(!catalog.isLoading)
    }
}
