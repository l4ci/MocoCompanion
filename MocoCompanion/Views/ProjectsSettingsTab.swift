import SwiftUI

/// Projects settings tab: shows synced projects with refresh.
struct ProjectsSettingsTab: View {
    var projects: [MocoProject]
    var isLoading: Bool
    var onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(projects.count) \(String(localized: "projects.syncedCount"))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await onRefresh() }
                } label: {
                    Label(String(localized: "projects.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if !projects.isEmpty {
                List {
                    ForEach(projects, id: \.id) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(project.customer.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            let activeTasks = project.tasks.filter(\.active)
                            if !activeTasks.isEmpty {
                                Text(activeTasks.map(\.name).joined(separator: ", "))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            } else if isLoading {
                Spacer()
                ProgressView("Loading projects…")
                Spacer()
            } else {
                Spacer()
                Text(String(localized: "projects.noProjects"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
        }
    }
}
