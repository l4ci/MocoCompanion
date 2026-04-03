import SwiftUI

/// Inline project search field with filtered results dropdown.
/// Used inside ActivityEditOverlay for project reassignment.
struct ProjectSearchField: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let projects: [MocoProject]
    var onSelect: (MocoProject) -> Void

    @FocusState private var isFocused: Bool

    /// Filtered projects for inline search.
    private var filteredProjects: [MocoProject] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        return projects.filter {
            $0.name.lowercased().contains(query) || $0.customer.name.lowercased().contains(query)
        }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField(String(localized: "edit.searchProjects"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onExitCommand {
                        isSearching = false
                    }

                Button {
                    isSearching = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "a11y.cancelSearch"))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if !filteredProjects.isEmpty {
                VStack(spacing: 0) {
                    ForEach(filteredProjects) { project in
                        Button {
                            onSelect(project)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(project.customer.name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(project.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(project.customer.name), \(project.name)")
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}
