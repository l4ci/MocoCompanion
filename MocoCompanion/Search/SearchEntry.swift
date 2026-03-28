import Foundation

/// A flattened entry representing one selectable Project > Task combination.
/// Built from MocoProject data for display and fuzzy search.
struct SearchEntry: ProjectTaskRef, Sendable {
    let projectId: Int
    let taskId: Int
    let customerName: String
    let projectName: String
    let taskName: String

    /// Searchable text for fuzzy matching (same as display but lowercased).
    var searchText: String {
        displayText.lowercased()
    }

    /// Create a SearchEntry from any ProjectTaskRef.
    init(from ref: any ProjectTaskRef) {
        self.projectId = ref.projectId
        self.taskId = ref.taskId
        self.customerName = ref.customerName
        self.projectName = ref.projectName
        self.taskName = ref.taskName
    }

    init(projectId: Int, taskId: Int, customerName: String, projectName: String, taskName: String) {
        self.projectId = projectId
        self.taskId = taskId
        self.customerName = customerName
        self.projectName = projectName
        self.taskName = taskName
    }

    /// Build search entries from a list of projects.
    /// Only includes active tasks.
    static func from(projects: [MocoProject]) -> [SearchEntry] {
        projects.flatMap { project in
            project.tasks.filter(\.active).map { task in
                SearchEntry(
                    projectId: project.id,
                    taskId: task.id,
                    customerName: project.customer.name,
                    projectName: project.name,
                    taskName: task.name
                )
            }
        }
    }
}
