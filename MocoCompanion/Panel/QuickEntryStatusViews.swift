import SwiftUI

/// Collection of small status views used by QuickEntryView.
/// Each view handles a specific transient state: success, error, loading, no results, not configured, submitting.

// MARK: - Success View

struct QuickEntrySuccessView: View {
    let projectName: String

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22 + fontBoost))
            Text(String(localized: "success.timerStarted").replacingOccurrences(of: "%@", with: projectName))
                .font(.system(size: 15 + fontBoost, weight: .medium))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(20)
        .transition(.opacity)
    }
}

// MARK: - Error View

struct QuickEntryErrorView: View {
    let message: String
    var onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 22 + fontBoost))
                Text(message)
                    .font(.system(size: 15 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
            }
            Button(String(localized: "action.dismiss")) {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(20)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - No Results View

struct QuickEntryNoResultsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            Text(String(localized: "search.noResults"))
                .font(.system(size: 15 + fontBoost))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}

// MARK: - Loading View

struct QuickEntryLoadingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "search.loading"))
                    .font(.system(size: 15 + fontBoost))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Not Configured View

struct QuickEntryNotConfiguredView: View {
    let isConfigured: Bool

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.system(size: 15 + fontBoost))
                Text(isConfigured ? "Failed to load projects. Right-click menu bar icon → Refresh." : "Open Settings to configure your Moco API key.")
                    .font(.system(size: 13 + fontBoost))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Submitting Indicator

struct QuickEntrySubmittingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "action.creating"))
                    .font(.system(size: 13 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.vertical, 12)
        }
    }
}
