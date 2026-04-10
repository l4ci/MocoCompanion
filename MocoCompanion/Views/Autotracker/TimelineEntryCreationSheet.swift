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
        let endMinutes = (TimelineViewModel.minutesSinceMidnight(from: startTime) ?? 0) + durationMinutes
        return TimelineViewModel.timeString(fromMinutes: endMinutes)
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
