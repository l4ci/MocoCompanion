import SwiftUI

/// Collection of small status views used by QuickEntryView.
/// Each view handles a specific transient state: success, error, loading, no results, not configured, submitting.

// MARK: - Success View

struct QuickEntrySuccessView: View {
    let projectName: String

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22 + fontBoost))
                .scaleEffect(appeared ? 1.0 : 0.3)
                .opacity(appeared ? 1.0 : 0)

            Text(String(localized: "success.timerStarted \(projectName)"))
                .font(.system(size: 15 + fontBoost, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .opacity(appeared ? 1.0 : 0)
                .offset(x: appeared ? 0 : -4)
        }
        .padding(20)
        .transition(.opacity)
        .onAppear {
            animateAccessibly(reduceMotion, .easeOut(duration: 0.3)) {
                appeared = true
            }
        }
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
        .accessibilityLabel(String(localized: "a11y.error \(message)"))
    }
}

// MARK: - No Results View

struct QuickEntryNoResultsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    /// Rotating tips shown below the "no results" message.
    private static let tips: [String] = [
        String(localized: "search.tip.shorter"),
        String(localized: "search.tip.customer"),
        String(localized: "search.tip.acronym"),
    ]

    @State private var tipIndex = Int.random(in: 0..<3)

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            VStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 24 + fontBoost, weight: .ultraLight))
                    .foregroundStyle(theme.textTertiary.opacity(0.5))

                Text(String(localized: "search.noResults"))
                    .font(.system(size: 14 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textSecondary)

                Text(Self.tips[tipIndex])
                    .font(.system(size: 12 + fontBoost))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
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
    var onRetry: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)
            VStack(spacing: 10) {
                Image(systemName: isConfigured ? "arrow.clockwise.circle" : "key")
                    .font(.system(size: 20 + fontBoost, weight: .light))
                    .foregroundStyle(isConfigured ? .orange.opacity(0.7) : theme.textTertiary.opacity(0.6))
                Text(isConfigured ? String(localized: "search.failedToLoad") : String(localized: "search.configureApi"))
                    .font(.system(size: 13 + fontBoost))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if isConfigured, let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Text(String(localized: "action.retry"))
                            .font(.system(size: 13 + fontBoost, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "a11y.retry"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
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
