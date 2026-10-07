import SwiftUI

/// The SwiftUI content view for the quick-entry popup panel.
/// Orchestrates the quick-entry flow using QuickEntryStateMachine for state
/// and delegates to extracted subviews for presentation.
struct QuickEntryView: View {
    @Bindable var appState: AppState
    var favoritesManager: FavoritesManager
    @Binding var activeTab: PanelContentView.PanelTab
    @Binding var initialSearchText: String
    /// Pre-selected entry from Today's planned tasks — enters description phase immediately.
    @Binding var preSelectedEntry: SearchEntry?

    /// State machine owning all quick-entry state and computed properties.
    /// Created once per view identity via @State, initialized in onAppear.
    @State private var sm: QuickEntryStateMachine
    @State private var submissionTask: Task<Void, Never>?
    @State private var submissionID: UUID?
    @Environment(\.panelDismissalScope) private var dismissalScope

    @FocusState private var focusedField: QuickEntryStateMachine.FocusField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(appState: AppState, favoritesManager: FavoritesManager, activeTab: Binding<PanelContentView.PanelTab>, initialSearchText: Binding<String> = .constant(""), preSelectedEntry: Binding<SearchEntry?> = .constant(nil)) {
        self.appState = appState
        self.favoritesManager = favoritesManager
        self._activeTab = activeTab
        self._initialSearchText = initialSearchText
        self._preSelectedEntry = preSelectedEntry
        self._sm = State(initialValue: QuickEntryStateMachine(
            commands: LiveQuickEntryCommands(
                timerService: appState.timerService,
                activityService: appState.activityService,
                notificationDispatcher: appState.notificationDispatcher
            ),
            dataSource: LiveQuickEntryDataSource(
                favoritesManager: favoritesManager,
                settings: appState.settings,
                recentEntriesTracker: appState.recentEntriesTracker,
                descriptionStore: appState.descriptionStore,
                entriesProvider: { [weak appState] in appState?.catalog.searchEntries ?? [] },
                searchFn: { [weak appState] query in appState?.search(query: query) ?? [] }
            )
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if case .success(let projectName) = sm.phase {
                QuickEntrySuccessView(projectName: projectName)
            } else if case .error(let message) = sm.phase {
                QuickEntryErrorView(message: message) {
                    animateAccessibly(reduceMotion) {
                        sm.phase = .searching
                    }
                    focusedField = .search
                }
            } else {
                // Fuzzy search runs on every read; evaluate it once per render.
                let items = sm.displayItems
                SearchFieldView(
                    searchText: $sm.searchText,
                    selectedIndex: $sm.selectedIndex,
                    activeTab: $activeTab,
                    isSearchEmpty: sm.isSearchEmpty,
                    hasActiveTimer: sm.hasActiveTimer,
                    hasMinSearchChars: sm.hasMinSearchChars,
                    displayItemCount: items.count,
                    avatarImage: appState.session.cachedAvatarImage,
                    userFirstname: appState.session.currentUserProfile?.firstname,
                    showKeyboardHints: appState.settings.showKeyboardHints,
                    onSubmit: handleSearchSubmit,
                    onMoveSelection: { sm.moveSelection(by: $0) },
                    onSelectByIndex: { _ = sm.selectByIndex($0); focusAfterSelect() },
                    onSelectCurrentResult: { selectCurrentResult() },
                    focusedField: $focusedField
                )

                if let warning = appState.yesterdayService.warning {
                    YesterdayBannerView(warning: warning, onDismiss: { appState.yesterdayService.warning = nil })
                }

                if sm.phase.isSearching && sm.isSearchEmpty {
                    TimerHintSection(
                        timerState: appState.timerService.timerState,
                        currentActivity: appState.timerService.currentActivity,
                        selectedIndex: $sm.selectedIndex
                    )
                }

                if appState.catalog.isLoading && appState.catalog.projects.isEmpty {
                    QuickEntryLoadingView()
                } else if appState.catalog.projects.isEmpty && !appState.catalog.isLoading {
                    QuickEntryNotConfiguredView(
                        isConfigured: appState.settings.isConfigured,
                        onRetry: {
                            Task { await appState.fetchProjects() }
                        }
                    )
                } else if sm.phase.isSearching && !items.isEmpty {
                    SearchResultsListView(
                        items: items,
                        selectedIndex: $sm.selectedIndex,
                        hoveredIndex: $sm.hoveredIndex,
                        favoritesManager: favoritesManager,
                        budgetService: appState.budgetService,
                        onSelectCurrent: { selectCurrentResult() },
                        showingShortcuts: sm.showingFavorites || sm.showingRecents
                    )
                }

                if sm.phase.isSearching && items.isEmpty && sm.hasMinSearchChars && !appState.catalog.projects.isEmpty {
                    QuickEntryNoResultsView()
                }


                if sm.phase.isDescribing, let entry = sm.selectedEntry {
                    SelectedEntryBannerView(entry: entry, favoritesManager: favoritesManager)
                    DescriptionFieldView(
                        descriptionText: $sm.descriptionText,
                        isManualMode: $sm.isManualMode,
                        manualHours: $sm.manualHours,
                        autocompleteSuggestion: sm.autocompleteSuggestion,
                        extractedTag: sm.extractedTag,
                        onSubmit: handleDescriptionSubmit,
                        onAcceptAutocomplete: { sm.acceptAutocomplete() },
                        onTextChanged: { sm.updateAutocompleteSuggestion() },
                        focusedField: $focusedField
                    )
                }

                if sm.isSubmitting {
                    QuickEntrySubmittingView()
                }
            }
        }
        .disabled(sm.isSubmitting)
        .onChange(of: sm.isSubmitting) { _, submitting in
            // Disabling the view drops the focused field. After a failed submit
            // that returns to .describing, give focus back or Enter/Escape are lost.
            guard !submitting else { return }
            Task { @MainActor in
                // Wait until the view is enabled again, then re-check the phase:
                // Escape may have moved on to the search list in the meantime.
                try? await Task.sleep(for: .milliseconds(50))
                if sm.phase.isDescribing {
                    focusedField = sm.isManualMode ? .hours : .description
                }
            }
        }
        .accessibleAnimation(reduceMotion, value: sm.phase.animationKey)
        .onDisappear {
            cancelSubmission()
        }
        .onAppear {
            cancelSubmission()
            sm.reset()
            // Pre-selected entry from planned task — go straight to description phase
            if let entry = preSelectedEntry {
                preSelectedEntry = nil
                sm.selectEntry(entry)
                setFocusAfterDelay($focusedField, to: .description)
            } else {
                setFocusAfterDelay($focusedField, to: .search)
            }
            // Pre-fill search from type-to-search in Today tab.
            // Set text AFTER focus so the select-all from focus fires on empty text,
            // then the typed character appears with cursor at the end.
            if !initialSearchText.isEmpty {
                let prefill = initialSearchText
                initialSearchText = ""
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    sm.searchText = prefill
                }
            }
            if appState.catalog.projects.isEmpty && !appState.catalog.isLoading {
                Task { await appState.fetchProjects() }
            }
        }
        .onExitCommand {
            cancelSubmission()
            if sm.phase.isDescribing {
                animateAccessibly(reduceMotion) {
                    sm.phase = .searching
                    sm.selectedEntry = nil
                }
                focusedField = .search
            } else {
                dismissalScope?.makeDismissAction()()
            }
        }
    }

    // MARK: - Actions

    private func handleSearchSubmit() {
        if sm.isSearchEmpty {
            if sm.handleEmptySubmit() { return }
            if sm.selectedIndex >= 0 && !sm.displayItems.isEmpty {
                selectCurrentResult()
                return
            }
            return
        }
        if !sm.displayItems.isEmpty {
            selectCurrentResult()
        }
    }

    private func selectCurrentResult() {
        animateAccessibly(reduceMotion) {
            _ = sm.selectCurrentResult()
        }
        focusAfterSelect()
    }

    private func focusAfterSelect() {
        setFocusAfterDelay($focusedField, to: .description)
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
        submissionID = nil
        sm.invalidateSubmission()
    }

    private func handleDescriptionSubmit() {
        guard submissionTask == nil else { return }
        let dismiss = dismissalScope?.makeDismissAction()
        let id = UUID()
        submissionID = id
        submissionTask = Task {
            defer {
                if submissionID == id {
                    submissionTask = nil
                    submissionID = nil
                }
            }
            guard !Task.isCancelled, submissionID == id else { return }
            let result = await sm.submitDescription()
            switch result {
            case .success:
                do { try await Task.sleep(for: .milliseconds(600)) }
                catch { return }
                guard !Task.isCancelled else { return }
                dismiss?()
            case .validationError, .apiError, .ignored:
                break
            }
        }
    }
}
