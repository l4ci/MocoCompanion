import SwiftUI
import os

/// Sheet presented after a drag-to-create gesture completes. Pre-filled with
/// time data from the drag; user selects project/task, optionally edits
/// description, then submits to create a ShadowEntry.
struct TimelineEntryCreationSheet: View {
    let date: String          // YYYY-MM-DD
    let startTime: String     // HH:mm
    let durationMinutes: Int
    let suggestedDescription: String
    let projectCatalog: ProjectCatalog
    var descriptionRequired: Bool = false

    /// (projectId, taskId, projectName, taskName, customerName, description)
    let onSubmit: (Int, Int, String, String, String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var searchText = ""
    @State private var selectedEntry: SearchEntry?
    @State private var descriptionText: String = ""
    @State private var errorMessage: String?
    @State private var hasInteracted: Bool = false

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
        .frame(width: 380, alignment: .topLeading)
        .onAppear {
            descriptionText = suggestedDescription
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDateHeader)
                .font(.system(size: Theme.FontSize.callout, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: 6) {
                Text("\(startTime) – \(endTime)")
                    .font(.system(size: Theme.FontSize.body, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)

                Text("(\(durationMinutes) min)")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: - Project Picker

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search projects…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

            let entries = projectCatalog.filter(query: searchText)
            if entries.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.prefix(20)) { entry in
                            ProjectPickerRow(
                                entry: entry,
                                isSelected: selectedEntry?.projectId == entry.projectId
                                    && selectedEntry?.taskId == entry.taskId,
                                onTap: { selectedEntry = entry }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
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
            TextField("Description (required)", text: $descriptionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.callout))
                .onChange(of: descriptionText) { _, _ in hasInteracted = true }
            if hasInteracted && descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(String(localized: "edit.description.required"))
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Create Entry") {
                guard let entry = selectedEntry else { return }
                onSubmit(
                    entry.projectId,
                    entry.taskId,
                    entry.projectName,
                    entry.taskName,
                    entry.customerName,
                    descriptionText
                )
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedEntry == nil || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Computed

    private var endTime: String {
        let endMinutes = (TimelineGeometry.minutesSinceMidnight(from: startTime) ?? 0) + durationMinutes
        return TimelineGeometry.timeString(fromMinutes: endMinutes)
    }

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
    var descriptionRequired: Bool = false

    let onSave: (EditedEntryFields) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    @State private var editedDate: Date
    @State private var startHour: Int
    @State private var startMinute: Int
    // (hasStartTime toggle removed — start time is always required in the edit sheet)
    @State private var showDeleteConfirmation: Bool = false
    @State private var durationMinutes: Int
    @State private var descriptionText: String
    @State private var hasInteracted: Bool = false
    @State private var selectedEntry: SearchEntry?
    @State private var isProjectPickerExpanded: Bool = false
    @State private var searchText: String = ""

    init(
        entry: ShadowEntry,
        fallbackDate: Date,
        projectCatalog: ProjectCatalog,
        linkedAppName: String? = nil,
        descriptionRequired: Bool = false,
        onSave: @escaping (EditedEntryFields) -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.fallbackDate = fallbackDate
        self.projectCatalog = projectCatalog
        self.linkedAppName = linkedAppName
        self.descriptionRequired = descriptionRequired
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        // Initialize state fields from the entry's current values so the
        // sheet opens showing what's already there.
        let parsedDate = Self.parseDate(entry.date) ?? fallbackDate
        _editedDate = State(initialValue: parsedDate)

        if let timeStr = entry.startTime,
           let total = TimelineGeometry.minutesSinceMidnight(from: timeStr) {
            _startHour = State(initialValue: total / 60)
            _startMinute = State(initialValue: total % 60)
        } else {
            _startHour = State(initialValue: 9)
            _startMinute = State(initialValue: 0)
        }

        _durationMinutes = State(initialValue: max(entry.seconds / 60, 1))
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

                VStack(alignment: .leading, spacing: 3) {
                    Text("Start")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                    HStack(spacing: 2) {
                        TextField("", value: $startHour, format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                        Text(":")
                            .foregroundStyle(theme.textTertiary)
                        TextField("", value: $startMinute, format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(.system(size: Theme.FontSize.callout, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Duration")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                    HStack(spacing: 4) {
                        TextField("", value: $durationMinutes, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                        Text("min")
                            .font(.system(size: Theme.FontSize.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Spacer(minLength: 0)
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

            TextField("Search projects…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

            let entries = projectCatalog.filter(query: searchText)
            if entries.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.prefix(20)) { row in
                            ProjectPickerRow(
                                entry: row,
                                isSelected: selectedEntry?.projectId == row.projectId
                                    && selectedEntry?.taskId == row.taskId,
                                onTap: {
                                    selectedEntry = row
                                    isProjectPickerExpanded = false
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
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
            TextField("Description (required)", text: $descriptionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.callout))
                .onChange(of: descriptionText) { _, _ in hasInteracted = true }
            if hasInteracted && descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(String(localized: "edit.description.required"))
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") {
                guard let selected = selectedEntry else { return }
                let dateStr = TimelineGeometry.dateString(from: editedDate)
                let startTimeStr: String? = String(
                    format: "%02d:%02d",
                    max(0, min(23, startHour)),
                    max(0, min(59, startMinute))
                )
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
            .keyboardShortcut(.defaultAction)
            .disabled(selectedEntry == nil || durationMinutes <= 0 || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
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
