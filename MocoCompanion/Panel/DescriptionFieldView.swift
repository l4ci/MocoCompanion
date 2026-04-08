import SwiftUI

/// The "What are you working on?" description input with autocomplete ghost text, tag display,
/// and optional manual hours entry (no timer mode).
struct DescriptionFieldView: View {
    @Binding var descriptionText: String
    @Binding var isManualMode: Bool
    @Binding var manualHours: String
    let autocompleteSuggestion: String?
    let extractedTag: String?

    var onSubmit: () -> Void
    var onAcceptAutocomplete: () -> Bool
    var onTextChanged: () -> Void

    @FocusState.Binding var focusedField: QuickEntryStateMachine.FocusField?
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bodySize: CGFloat { 15 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with mode toggle
                HStack {
                    Text(String(localized: "description.prompt"))
                        .font(.system(size: captionSize, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)

                    Spacer()

                    // Timer / Manual toggle
                    Button {
                        animateAccessibly(reduceMotion) {
                            isManualMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isManualMode ? "clock" : "timer")
                                .font(.system(size: captionSize))
                            Text(isManualMode ? String(localized: "mode.manual") : String(localized: "mode.timer"))
                                .font(.system(size: captionSize, weight: .medium))
                        }
                        .foregroundStyle(isManualMode ? .orange : theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isManualMode ? Color.orange.opacity(0.1) : theme.surface)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isManualMode ? "Switch to timer mode" : "Switch to manual hours entry")
                }

                ZStack(alignment: .topLeading) {
                    // Ghost text for autocomplete suggestion
                    if let suggestion = autocompleteSuggestion, !descriptionText.isEmpty {
                        Text(suggestion)
                            .font(.system(size: bodySize))
                            .foregroundStyle(theme.textTertiary.opacity(0.5))
                            .lineLimit(2...4)
                            .padding(.top, 1)
                    }

                    TextField(String(localized: "description.placeholder"), text: $descriptionText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: bodySize))
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .description)
                        .accessibilityLabel(String(localized: "a11y.activityDescription"))
                        .onSubmit { onSubmit() }
                        .onChange(of: descriptionText) {
                            onTextChanged()
                        }
                        .onKeyPress(.tab) {
                            if onAcceptAutocomplete() {
                                return .handled
                            }
                            // Tab toggles manual mode and focuses hours
                            animateAccessibly(reduceMotion) {
                                isManualMode = true
                            }
                            focusedField = .hours
                            return .handled
                        }
                }

                // Manual hours input
                if isManualMode {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: captionSize))
                            .foregroundStyle(theme.textTertiary)

                        TextField(String(localized: "hours.placeholder"), text: $manualHours)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: bodySize, design: .monospaced))
                            .frame(width: 110)
                            .focused($focusedField, equals: .hours)
                            .accessibilityLabel(String(localized: "a11y.hoursToBook"))
                            .onSubmit { onSubmit() }
                            .onKeyPress(.tab) {
                                // Tab from hours goes back to description
                                focusedField = .description
                                return .handled
                            }

                        Spacer()
                    }
                }

                // Bottom hints
                HStack(spacing: 12) {
                    if let tag = extractedTag {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: captionSize))
                            Text(tag)
                                .font(.system(size: captionSize, weight: .medium))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }

                    if autocompleteSuggestion != nil {
                        Text(String(localized: "description.acceptSuggestion"))
                            .font(.system(size: captionSize, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }

                    Spacer()

                    if isManualMode {
                        Text(String(localized: "description.bookEntry"))
                            .font(.system(size: captionSize, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Text(String(localized: "description.startTimer"))
                            .font(.system(size: captionSize, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}
