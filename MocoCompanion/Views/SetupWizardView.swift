import SwiftUI

/// Two-step onboarding wizard shown when the app launches unconfigured.
/// Step 1: Moco domain input. Step 2: API key input with link to integrations page.
/// The wizard is the app's first impression — warmer and more generous than the
/// utility panel, but still native and fast.
struct SetupWizardView: View {
    @Bindable var settings: SettingsStore
    var onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Derived from the window's actual color scheme — the theme
    /// environment key defaults to light and isn't set above this view.
    private var theme: Theme { Theme(colorScheme: colorScheme) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: WizardStep = .domain
    @State private var domainInput = ""
    @State private var apiKeyInput = ""
    @State private var iconAppeared = false

    private enum WizardStep: Int, CaseIterable {
        case domain = 0
        case apiKey = 1
    }

    /// Parse subdomain from user input — accepts bare subdomain, full host, or full URL.
    private var parsedSubdomain: String {
        MocoClient.parseSubdomain(domainInput)
    }

    private var canProceedDomain: Bool { MocoClient.isValidSubdomain(parsedSubdomain) }
    private var canConnect: Bool { !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            // App icon — slightly larger, with a gentle entrance
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .scaleEffect(iconAppeared ? 1.0 : 0.8)
                .opacity(iconAppeared ? 1.0 : 0)

            Spacer().frame(height: 28)

            // Step content
            switch step {
            case .domain:
                domainStep
            case .apiKey:
                apiKeyStep
            }

            Spacer().frame(height: 32)

            // Step progress — connected line with dots
            stepIndicator

            Spacer().frame(height: 28)
        }
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 24)
        .withTheme(colorScheme: colorScheme)
        .animation(.easeInOut(duration: Theme.Motion.standard), value: step)
        .onAppear {
            animateAccessibly(reduceMotion, .easeOut(duration: 0.4).delay(0.1)) {
                iconAppeared = true
            }
        }
    }

    // MARK: - Step Progress

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            // Step 1 dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)

            // Connecting line
            Rectangle()
                .fill(step == .apiKey ? Color.accentColor : theme.divider)
                .frame(width: 32, height: 2)

            // Step 2 dot
            Circle()
                .fill(step == .apiKey ? Color.accentColor : theme.divider)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Step 1: Domain

    @ViewBuilder
    private var domainStep: some View {
        Text(String(localized: "setup.welcome"))
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(theme.textPrimary)

        Spacer().frame(height: 6)

        Text(String(localized: "setup.domainPrompt"))
            .font(.system(size: Theme.FontSize.callout))
            .foregroundStyle(theme.textSecondary)

        Spacer().frame(height: 24)

        VStack(spacing: 6) {
            TextField(String(localized: "setup.domainPlaceholder"), text: $domainInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .frame(width: 300)
                .onSubmit { if canProceedDomain { advanceToApiKey() } }

            if !parsedSubdomain.isEmpty && !MocoClient.isValidSubdomain(parsedSubdomain) {
                Text(String(localized: "setup.invalidSubdomain"))
                    .font(.system(size: Theme.FontSize.subhead))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }

        Spacer().frame(height: 20)

        Button(action: advanceToApiKey) {
            Text(String(localized: "setup.next"))
                .font(.system(size: Theme.FontSize.body, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 120, height: 34)
                .background(canProceedDomain ? Color.accentColor : theme.buttonDisabled)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canProceedDomain)
    }

    // MARK: - Step 2: API Key

    @ViewBuilder
    private var apiKeyStep: some View {
        Text(String(localized: "setup.apiKeyPrompt"))
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(theme.textPrimary)

        Spacer().frame(height: 6)

        HStack(spacing: 4) {
            Text(String(localized: "setup.apiKeyLink"))
                .font(.system(size: Theme.FontSize.callout))
                .foregroundStyle(theme.textSecondary)

            if let integrationURL = URL(string: "https://\(parsedSubdomain).mocoapp.com/profile/integrations") {
                Link(
                    integrationURL.absoluteString,
                    destination: integrationURL
                )
                .font(.system(size: Theme.FontSize.callout))
            }
        }

        Spacer().frame(height: 24)

        SecureField("API Key", text: $apiKeyInput)
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .onSubmit { if canConnect { connect() } }

        Spacer().frame(height: 20)

        HStack(spacing: 12) {
            Button(action: { step = .domain }) {
                Text(String(localized: "setup.back"))
                    .font(.system(size: Theme.FontSize.body, weight: .medium))
                    .frame(width: 100, height: 34)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: connect) {
                Text(String(localized: "setup.connect"))
                    .font(.system(size: Theme.FontSize.body, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 34)
                    .background(canConnect ? Color.accentColor : theme.buttonDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canConnect)
        }
    }

    // MARK: - Actions

    private func advanceToApiKey() {
        guard canProceedDomain else { return }
        step = .apiKey
    }

    private func connect() {
        guard canConnect else { return }
        settings.subdomain = parsedSubdomain
        settings.apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete()
    }
}
