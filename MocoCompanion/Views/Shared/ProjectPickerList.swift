import SwiftUI

/// Pure selection logic for the keyboard-driven project picker.
enum ProjectPickerSelection {
    /// Moves the selection by `offset` rows within `results`, clamped at both ends (no wrap).
    /// With no current selection (or one that is not in `results`) the first row is selected.
    static func step(_ current: SearchEntry?, in results: [SearchEntry], by offset: Int) -> SearchEntry? {
        guard !results.isEmpty else { return nil }
        guard let current, let index = results.firstIndex(where: { $0.id == current.id }) else {
            return results[0]
        }
        return results[min(max(index + offset, 0), results.count - 1)]
    }

    /// Selection after the query changed: the top result, or `nil` when there are no results.
    /// An empty query clears the selection when `clearsOnEmptyQuery`, otherwise keeps `current`.
    static func afterQueryChange(
        query: String,
        results: [SearchEntry],
        current: SearchEntry?,
        clearsOnEmptyQuery: Bool
    ) -> SearchEntry? {
        if query.isEmpty { return clearsOnEmptyQuery ? nil : current }
        return results.first
    }
}

/// Keyboard-first project/task picker: search field plus result list.
///
/// Typing selects the top match, up/down arrows move the selection, Return confirms it
/// via `onCommit`. Rows are never focusable and hovering never changes the selection.
struct ProjectPickerList<Field: Hashable>: View {
    /// Maximum number of rows shown.
    static var maxRows: Int { 20 }

    let projectCatalog: ProjectCatalog
    var favorites: [SearchEntry] = []
    /// Edit sheets keep their preselection when the query is empty; create sheets clear it.
    var clearsSelectionOnEmptyQuery: Bool = true
    @Binding var searchText: String
    @Binding var selectedEntry: SearchEntry?
    var focus: FocusState<Field?>.Binding
    let searchField: Field
    /// Return pressed with a selection.
    var onCommit: () -> Void
    /// Row clicked.
    var onPick: (SearchEntry) -> Void = { _ in }

    @Environment(\.theme) private var theme

    private var results: [SearchEntry] {
        Array(projectCatalog.filter(query: searchText, favorites: favorites).prefix(Self.maxRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search projects…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))
                .focused(focus, equals: searchField)
                .onChange(of: searchText) { _, query in
                    selectedEntry = ProjectPickerSelection.afterQueryChange(
                        query: query,
                        results: results,
                        current: selectedEntry,
                        clearsOnEmptyQuery: clearsSelectionOnEmptyQuery
                    )
                }
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onSubmit {
                    if selectedEntry != nil { onCommit() }
                }

            let rows = results
            if rows.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(rows) { row in
                                ProjectPickerRow(
                                    entry: row,
                                    isSelected: selectedEntry?.id == row.id,
                                    onTap: {
                                        selectedEntry = row
                                        onPick(row)
                                    }
                                )
                                .id(row.id)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: selectedEntry?.id) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        selectedEntry = ProjectPickerSelection.step(selectedEntry, in: results, by: offset)
        return .handled
    }
}
