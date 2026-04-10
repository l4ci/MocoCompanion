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

    /// (projectId, taskId, projectName, taskName, customerName, description)
    let onSubmit: (Int, Int, String, String, String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var searchText = ""
    @State private var selectedEntry: SearchEntry?
    @State private var descriptionText: String = ""
    @State private var errorMessage: String?

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

            let entries = filteredEntries
            if entries.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.prefix(20), id: \.taskId) { entry in
                            projectRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func projectRow(_ entry: SearchEntry) -> some View {
        let isSelected = selectedEntry?.projectId == entry.projectId
            && selectedEntry?.taskId == entry.taskId

        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.customerName)
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.projectName)
                        .font(.system(size: Theme.FontSize.callout, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("›")
                        .foregroundStyle(theme.textTertiary)
                    Text(entry.taskName)
                        .font(.system(size: Theme.FontSize.callout))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: Theme.FontSize.callout))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEntry = entry
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            TextField("Optional description", text: $descriptionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))
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
            .disabled(selectedEntry == nil)
        }
    }

    // MARK: - Computed

    private var endTime: String {
        let endMinutes = (TimelineGeometry.minutesSinceMidnight(from: startTime) ?? 0) + durationMinutes
        return TimelineGeometry.timeString(fromMinutes: endMinutes)
    }

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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: d)
    }

    private var filteredEntries: [SearchEntry] {
        let all = projectCatalog.searchEntries
        guard !searchText.isEmpty else { return all }
        let matches = FuzzyMatcher.search(query: searchText, in: all)
        return matches.map(\.entry)
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

    let onSave: (EditedEntryFields) -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    @State private var editedDate: Date
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var hasStartTime: Bool
    @State private var durationMinutes: Int
    @State private var descriptionText: String
    @State private var selectedEntry: SearchEntry?
    @State private var isProjectPickerExpanded: Bool = false
    @State private var searchText: String = ""

    init(
        entry: ShadowEntry,
        fallbackDate: Date,
        projectCatalog: ProjectCatalog,
        onSave: @escaping (EditedEntryFields) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entry = entry
        self.fallbackDate = fallbackDate
        self.projectCatalog = projectCatalog
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state fields from the entry's current values so the
        // sheet opens showing what's already there.
        let parsedDate = Self.parseDate(entry.date) ?? fallbackDate
        _editedDate = State(initialValue: parsedDate)

        if let timeStr = entry.startTime,
           let total = TimelineGeometry.minutesSinceMidnight(from: timeStr) {
            _startHour = State(initialValue: total / 60)
            _startMinute = State(initialValue: total % 60)
            _hasStartTime = State(initialValue: true)
        } else {
            _startHour = State(initialValue: 9)
            _startMinute = State(initialValue: 0)
            _hasStartTime = State(initialValue: false)
        }

        _durationMinutes = State(initialValue: max(entry.seconds / 60, 1))
        _descriptionText = State(initialValue: entry.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Entry")
                .font(.system(size: Theme.FontSize.callout, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            Divider()

            timeSection

            Divider()

            projectSection

            Divider()

            descriptionField

            Divider()

            buttonRow
        }
        .padding(16)
        .frame(width: 440, alignment: .topLeading)
        .onAppear {
            // Pre-select the current project/task from the catalog so the
            // collapsed view shows the entry's current assignment.
            selectedEntry = projectCatalog.searchEntries.first {
                $0.projectId == entry.projectId && $0.taskId == entry.taskId
            }
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
                    HStack(spacing: 4) {
                        Text("Start")
                            .font(.system(size: Theme.FontSize.caption))
                            .foregroundStyle(theme.textTertiary)
                        Toggle("", isOn: $hasStartTime)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    HStack(spacing: 2) {
                        TextField("", value: $startHour, format: .number)
                            .frame(width: 34)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!hasStartTime)
                        Text(":")
                            .foregroundStyle(theme.textTertiary)
                        TextField("", value: $startMinute, format: .number)
                            .frame(width: 34)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!hasStartTime)
                    }
                    .font(.system(size: Theme.FontSize.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Duration")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                    HStack(spacing: 4) {
                        TextField("", value: $durationMinutes, format: .number)
                            .frame(width: 50)
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

            let entries = filteredEntries
            if entries.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.prefix(20), id: \.taskId) { row in
                            projectRow(row)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func projectRow(_ row: SearchEntry) -> some View {
        let isSelected = selectedEntry?.projectId == row.projectId
            && selectedEntry?.taskId == row.taskId

        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.customerName)
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(row.projectName)
                        .font(.system(size: Theme.FontSize.callout, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("›")
                        .foregroundStyle(theme.textTertiary)
                    Text(row.taskName)
                        .font(.system(size: Theme.FontSize.callout))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: Theme.FontSize.callout))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEntry = row
            // Auto-collapse the picker after a selection to bring the user
            // back to the compact edit view.
            isProjectPickerExpanded = false
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            TextField("Optional description", text: $descriptionText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))
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
                let startTimeStr: String? = hasStartTime
                    ? String(format: "%02d:%02d",
                             max(0, min(23, startHour)),
                             max(0, min(59, startMinute)))
                    : nil
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
            .disabled(selectedEntry == nil || durationMinutes <= 0)
        }
    }

    // MARK: - Helpers

    private var filteredEntries: [SearchEntry] {
        let all = projectCatalog.searchEntries
        guard !searchText.isEmpty else { return all }
        let matches = FuzzyMatcher.search(query: searchText, in: all)
        return matches.map(\.entry)
    }

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
