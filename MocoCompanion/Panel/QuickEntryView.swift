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
                if let warning = appState.yesterdayService.warning {
                    YesterdayBannerView(warning: warning, onDismiss: { appState.yesterdayService.warning = nil })
                }

                SearchFieldView(
                    searchText: $sm.searchText,
                    selectedIndex: $sm.selectedIndex,
                    activeTab: $activeTab,
                    isSearchEmpty: sm.isSearchEmpty,
                    hasActiveTimer: sm.hasActiveTimer,
                    hasMinSearchChars: sm.hasMinSearchChars,
                    displayItemCount: sm.displayItems.count,
                    avatarImage: appState.session.cachedAvatarImage,
                    userFirstname: appState.session.currentUserProfile?.firstname,
                    onSubmit: handleSearchSubmit,
                    onMoveSelection: { sm.moveSelection(by: $0) },
                    onSelectByIndex: { _ = sm.selectByIndex($0); focusAfterSelect() },
                    onSelectCurrentResult: { selectCurrentResult() },
                    focusedField: $focusedField
                )

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
                } else if sm.phase.isSearching && !sm.searchResults.isEmpty {
                    SearchResultsListView(
                        items: sm.displayItems,
                        selectedIndex: $sm.selectedIndex,
                        hoveredIndex: $sm.hoveredIndex,
                        favoritesManager: favoritesManager,
                        budgetService: appState.budgetService,
                        onSelectCurrent: { selectCurrentResult() },
                        showingShortcuts: sm.showingFavorites || sm.showingRecents
                    )
                }

                if sm.phase.isSearching && sm.searchResults.isEmpty && sm.hasMinSearchChars && !appState.catalog.projects.isEmpty {
                    QuickEntryNoResultsView()
                }

                // Reserve space when typing below min-char threshold to prevent panel collapse
                if sm.phase.isSearching && !sm.isSearchEmpty && !sm.hasMinSearchChars {
                    Spacer()
                        .frame(height: 40)
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
        .accessibleAnimation(reduceMotion, value: sm.phase.animationKey)
        .onAppear {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sm.searchText = prefill
                }
            }
            if appState.catalog.projects.isEmpty && !appState.catalog.isLoading {
                Task { await appState.fetchProjects() }
            }
        }
        .onExitCommand {
            if sm.phase.isDescribing {
                animateAccessibly(reduceMotion) {
                    sm.phase = .searching
                    sm.selectedEntry = nil
                }
                focusedField = .search
            } else {
                NSApp.keyWindow?.close()
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

    private func handleDescriptionSubmit() {
        Task {
            let result = await sm.submitDescription()
            switch result {
            case .success:
                try? await Task.sleep(for: .milliseconds(600))
                NSApp.keyWindow?.close()
            case .validationError, .apiError:
                break
            }
        }
    }
}
