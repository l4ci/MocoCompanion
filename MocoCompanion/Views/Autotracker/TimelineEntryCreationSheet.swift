import SwiftUI
import os

/// Focusable fields shared by the create and edit sheets.
private enum EntrySheetField: Hashable {
    case search
    case description
}

/// Sheet presented after a drag-to-create gesture completes. Pre-filled with
/// time data from the drag; user selects project/task, optionally edits
/// description, then submits to create a ShadowEntry.
struct TimelineEntryCreationSheet: View {
    let date: String          // YYYY-MM-DD
    let suggestedDescription: String
    let projectCatalog: ProjectCatalog
    var favorites: [SearchEntry] = []
    var descriptionRequired: Bool = false

    /// (projectId, taskId, projectName, taskName, customerName, description,
    /// startTime "HH:mm", durationMinutes) — time reflects the user's edits.
    let onSubmit: (Int, Int, String, String, String, String, String, Int) -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var startMinutes: Int
    @State private var durationMinutes: Int
    @State private var searchText = ""
    @State private var selectedEntry: SearchEntry?
    @State private var descriptionText: String = ""
    @State private var errorMessage: String?
    @State private var hasInteracted: Bool = false
    @FocusState private var focus: EntrySheetField?

    init(
        date: String,
        startTime: String,
        durationMinutes: Int,
        suggestedDescription: String,
        projectCatalog: ProjectCatalog,
        favorites: [SearchEntry] = [],
        descriptionRequired: Bool = false,
        onSubmit: @escaping (Int, Int, String, String, String, String, String, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.date = date
        self.suggestedDescription = suggestedDescription
        self.projectCatalog = projectCatalog
        self.favorites = favorites
        self.descriptionRequired = descriptionRequired
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        let model = TimeRangeModel(
            start: TimelineGeometry.minutesSinceMidnight(from: startTime) ?? 0,
            duration: durationMinutes
        )
        _startMinutes = State(initialValue: model.start)
        _durationMinutes = State(initialValue: model.duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            projectPicker
            descriptionField
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
            Divider()
            buttonRow
        }
        .padding(16)
        .frame(width: 440, alignment: .topLeading)
        .onAppear {
            descriptionText = suggestedDescription
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                focus = .search
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDateHeader)
                .font(.system(size: Theme.FontSize.callout, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            TimeRangeEditor(startMinutes: $startMinutes, durationMinutes: $durationMinutes)
        }
    }

    // MARK: - Project Picker

    private var projectPicker: some View {
        ProjectPickerList(
            projectCatalog: projectCatalog,
            favorites: favorites,
            searchText: $searchText,
            selectedEntry: $selectedEntry,
            focus: $focus,
            searchField: .search,
            onCommit: { focus = .description }
        )
    }


    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text("Description")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Text("*")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(.red)
            }
            TextField("Description (required)", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .font(.system(size: Theme.FontSize.body))
                .focused($focus, equals: .description)
                .onChange(of: descriptionText) { _, _ in hasInteracted = true }
                .onSubmit { submit() }
            if hasInteracted && descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(String(localized: "edit.description.required"))
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Buttons

    private var canSubmit: Bool {
        selectedEntry != nil && durationMinutes > 0
            && !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        guard canSubmit, let entry = selectedEntry else { return }
        onSubmit(
            entry.projectId,
            entry.taskId,
            entry.projectName,
            entry.taskName,
            entry.customerName,
            descriptionText,
            TimeRangeModel.format(startMinutes),
            durationMinutes
        )
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Create Entry") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
    }

    // MARK: - Computed

    private static let headerDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d"
        return fmt
    }()

    private var formattedDateHeader: String {
        // Parse YYYY-MM-DD and format nicely
        let parts = date.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return date
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let d = Calendar.current.date(from: comps) else { return date }
        return Self.headerDateFormatter.string(from: d)
    }
}

// MARK: - Edit Sheet

/// Payload the edit sheet produces on Save. Carries every field the user
/// may have touched.
struct EditedEntryFields {
    let projectId: Int
    let taskId: Int
    let projectName: String
    let taskName: String
    let customerName: String
    let description: String
    /// YYYY-MM-DD
    let date: String
    /// HH:mm, or nil to keep the entry unassigned
    let startTime: String?
    let durationMinutes: Int
}

/// Sheet for editing an existing `ShadowEntry`. Supports changing the date,
/// start time, duration, project/task, and description. Used for both
/// positioned entries (via the timeline context menu) and unpositioned
/// entries (via the unassigned-list context menu, where start time can be
/// set for the first time).
///
/// Project is shown collapsed by default — the user sees their current
/// project/task at a glance, and only expands into the searchable picker
/// when they explicitly tap the edit button.
struct TimelineEntryEditSheet: View {
    let entry: ShadowEntry
    /// Fallback date used if the entry has no parseable date of its own
    /// (shouldn't happen in practice; safety net).
    let fallbackDate: Date
    let projectCatalog: ProjectCatalog
    /// Name of the linked app usage block, if any. Display-only.
    var linkedAppName: String? = nil
    var favorites: [SearchEntry] = []
    var descriptionRequired: Bool = false

    let onSave: (EditedEntryFields) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    @State private var editedDate: Date
    /// Minutes since midnight. Entries without a start time open at 09:00;
    /// start time is always required in the edit sheet.
    @State private var startMinutes: Int
    @State private var showDeleteConfirmation: Bool = false
    @State private var durationMinutes: Int
    @State private var descriptionText: String
    @State private var hasInteracted: Bool = false
    @State private var selectedEntry: SearchEntry?
    @State private var isProjectPickerExpanded: Bool = false
    @State private var searchText: String = ""
    @FocusState private var focus: EntrySheetField?

    init(
        entry: ShadowEntry,
        fallbackDate: Date,
        projectCatalog: ProjectCatalog,
        linkedAppName: String? = nil,
        favorites: [SearchEntry] = [],
        descriptionRequired: Bool = false,
        onSave: @escaping (EditedEntryFields) -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.fallbackDate = fallbackDate
        self.projectCatalog = projectCatalog
        self.linkedAppName = linkedAppName
        self.favorites = favorites
        self.descriptionRequired = descriptionRequired
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        // Initialize state fields from the entry's current values so the
        // sheet opens showing what's already there.
        let parsedDate = Self.parseDate(entry.date) ?? fallbackDate
        _editedDate = State(initialValue: parsedDate)

        let initialStart = entry.startTime.flatMap { TimelineGeometry.minutesSinceMidnight(from: $0) } ?? 9 * 60
        let range = TimeRangeModel(start: initialStart, duration: entry.seconds / 60)
        _startMinutes = State(initialValue: range.start)
        _durationMinutes = State(initialValue: range.duration)
        _descriptionText = State(initialValue: entry.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit Entry")
                    .font(.system(size: Theme.FontSize.title, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if onDelete != nil, !entry.isReadOnly {
                    Button("Delete Entry", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: Theme.FontSize.body))
                    .help("Delete entry")
                }
            }

            Divider()

            timeSection

            if let linkedAppName {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                    Text("Linked to recorded activity: \(linkedAppName)")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.vertical, 2)
            }

            Divider()

            projectSection

            Divider()

            descriptionField

            Divider()

            buttonRow
        }
        .padding(20)
        .frame(width: 520, alignment: .topLeading)
        .onAppear {
            // Pre-select the current project/task from the catalog so the
            // collapsed view shows the entry's current assignment.
            selectedEntry = projectCatalog.searchEntries.first {
                $0.projectId == entry.projectId && $0.taskId == entry.taskId
            }
        }
        .onChange(of: isProjectPickerExpanded) { _, expanded in
            if expanded {
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    focus = .search
                }
            }
        }
        .confirmationDialog(
            "Delete entry?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("You can undo this for 5 seconds before it is pushed to Moco.")
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Date")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                    DatePicker("", selection: $editedDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                TimeRangeEditor(startMinutes: $startMinutes, durationMinutes: $durationMinutes)
            }
        }
    }

    // MARK: - Project Section (collapsed by default)

    @ViewBuilder
    private var projectSection: some View {
        if isProjectPickerExpanded {
            projectPickerExpanded
        } else {
            projectDisplayCollapsed
        }
    }

    private var projectDisplayCollapsed: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Project")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let selected = selectedEntry {
                        Text(selected.customerName)
                            .font(.system(size: Theme.FontSize.caption))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(selected.projectName)
                                .font(.system(size: Theme.FontSize.callout, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            Text("›")
                                .foregroundStyle(theme.textTertiary)
                            Text(selected.taskName)
                                .font(.system(size: Theme.FontSize.callout))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("(no project selected)")
                            .font(.system(size: Theme.FontSize.callout))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    isProjectPickerExpanded = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Change")
                    }
                    .font(.system(size: Theme.FontSize.caption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(8)
            .background(
                theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            )
        }
    }

    private var projectPickerExpanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Project")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Done") {
                    isProjectPickerExpanded = false
                }
                .buttonStyle(.plain)
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(Color.accentColor)
            }

            ProjectPickerList(
                projectCatalog: projectCatalog,
                favorites: favorites,
                clearsSelectionOnEmptyQuery: false,
                searchText: $searchText,
                selectedEntry: $selectedEntry,
                focus: $focus,
                searchField: .search,
                onCommit: {
                    isProjectPickerExpanded = false
                    focus = .description
                },
                onPick: { _ in isProjectPickerExpanded = false }
            )
        }
    }


    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text("Description")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Text("*")
                    .font(.system(size: Theme.FontSize.caption, weight: .medium))
                    .foregroundStyle(.red)
            }
            TextField("Description (required)", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .font(.system(size: Theme.FontSize.body))
                .focused($focus, equals: .description)
                .onChange(of: descriptionText) { _, _ in hasInteracted = true }
                .onSubmit { save() }
            if hasInteracted && descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(String(localized: "edit.description.required"))
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Buttons

    private var canSave: Bool {
        selectedEntry != nil && durationMinutes > 0
            && !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard canSave, let selected = selectedEntry else { return }
        let dateStr = TimelineGeometry.dateString(from: editedDate)
        let startTimeStr: String? = TimeRangeModel.format(startMinutes)
        onSave(EditedEntryFields(
            projectId: selected.projectId,
            taskId: selected.taskId,
            projectName: selected.projectName,
            taskName: selected.taskName,
            customerName: selected.customerName,
            description: descriptionText,
            date: dateStr,
            startTime: startTimeStr,
            durationMinutes: max(durationMinutes, 1)
        ))
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    // MARK: - Helpers

    /// Parses "YYYY-MM-DD" into a `Date` at start-of-day in the current
    /// calendar. Returns nil for malformed input.
    private static func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)
    }
}
