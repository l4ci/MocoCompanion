import AppKit

/// Pure data describing what the menubar status item should display.
/// Computed from TimerService state — no AppKit dependencies (except NSColor for dot).
/// StatusItemController reads this and applies it to the NSStatusItem.
struct MenuBarDisplayState: Equatable {
    let iconName: String
    let title: String
    let accessibilityDescription: String
    /// Indicator dot color: red=idle, orange=paused, green=running.
    let dotColor: NSColor

    /// Compute the current display state from timer state.
    static func from(
        timerState: TimerState,
        currentActivity: ShadowEntry?
    ) -> MenuBarDisplayState {
        switch timerState {
        case .idle:
            return MenuBarDisplayState(
                iconName: "timer",
                title: "",
                accessibilityDescription: "Moco Timer",
                dotColor: .systemRed
            )

        case .running(_, let projectName):
            let label = formatMenuBarLabel(projectName: projectName, taskName: currentActivity?.taskName)
            let elapsed = computeElapsedString(from: currentActivity)
            return MenuBarDisplayState(
                iconName: "timer",
                title: " \(label) \(elapsed)",
                accessibilityDescription: "Timer Running",
                dotColor: .systemGreen
            )

        case .paused:
            return MenuBarDisplayState(
                iconName: "timer",
                title: "",
                accessibilityDescription: "Timer Paused",
                dotColor: .systemOrange
            )
        }
    }

    /// Compute the elapsed time string for a running activity.
    static func elapsedString(from activity: ShadowEntry?) -> String {
        computeElapsedString(from: activity)
    }

    /// Build just the project/task label portion of the running title,
    /// *without* the elapsed time. Exposed so the menu-bar elapsed-refresh
    /// loop can cache this string on state transitions and avoid the
    /// emoji-scalar scan on every 1 s tick — the label is constant for the
    /// duration of a running timer.
    static func runningLabel(projectName: String, taskName: String?) -> String {
        formatMenuBarLabel(projectName: projectName, taskName: taskName)
    }

    /// Compose the full menu-bar title from a cached running label plus a
    /// freshly-formatted elapsed string. Matches the exact format produced
    /// by `from(timerState:)`.
    static func runningTitle(label: String, elapsed: String) -> String {
        " \(label) \(elapsed)"
    }

    // MARK: - Private

    /// Format the menubar label: "Project · Ta…sk" — project emoji-only if available, task truncated in middle.
    private static func formatMenuBarLabel(projectName: String, taskName: String?, maxTotal: Int = 30) -> String {
        guard let taskName, !taskName.isEmpty else {
            return truncateEnd(projectName, max: maxTotal)
        }

        let separator = " · "
        let proj = projectEmoji(projectName) ?? truncateEnd(projectName, max: 10)
        let usedByProject = proj.count + separator.count
        let taskBudget = maxTotal - usedByProject

        let task = truncateMiddle(taskName, max: taskBudget)

        return "\(proj)\(separator)\(task)"
    }

    /// Extract the leading emoji from a project name, if any.
    /// "💬 Interne Meetings" → "💬", "#796 🧑‍🍳 Heads" → "🧑‍🍳", "Marketing" → nil
    private static func projectEmoji(_ name: String) -> String? {
        for character in name {
            // Skip ASCII characters (letters, digits, #, spaces, punctuation)
            if character.isASCII { continue }
            // Check if this grapheme cluster contains an emoji
            if character.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x23F }) {
                return String(character)
            }
        }
        return nil
    }

    /// Truncate at the end with ellipsis: "Very Long Na…"
    private static func truncateEnd(_ text: String, max: Int) -> String {
        guard text.count > max, max > 2 else { return text }
        return String(text.prefix(max - 1)) + "…"
    }

    /// Truncate in the middle: "Abstimm…Termine"
    private static func truncateMiddle(_ text: String, max: Int) -> String {
        guard text.count > max, max > 4 else { return text }
        let keepEach = (max - 1) / 2  // -1 for the ellipsis
        let prefix = text.prefix(keepEach)
        let suffix = text.suffix(keepEach)
        return "\(prefix)…\(suffix)"
    }

    private static func computeElapsedString(from activity: ShadowEntry?) -> String {
        guard let activity,
              let startedAt = activity.timerStartedAt,
              let start = DateUtilities.parseISO8601(startedAt) else { return "" }
        let previousSeconds = Double(activity.seconds)
        let liveDelta = Date.now.timeIntervalSince(start)
        return DateUtilities.formatElapsedCompact(previousSeconds + liveDelta)
    }
}
