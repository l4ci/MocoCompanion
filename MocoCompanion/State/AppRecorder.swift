import AppKit
import os

/// Passively records which app is frontmost, coalescing same-app segments.
@Observable
@MainActor
final class AppRecorder {
    private let logger = Logger(category: "AppRecorder")
    let store: AppRecordStore

    // MARK: - Observable state

    private(set) var isRecording = false
    private(set) var recordCount = 0
    private(set) var currentAppName: String?

    // MARK: - Coalescing

    private struct Segment {
        var bundleId: String
        var appName: String
        var startedAt: Date
        var lastSeenAt: Date
    }

    private var currentSegment: Segment?
    private let coalescingThreshold: TimeInterval = 10.0

    private let settings: SettingsStore?

    private static let systemFilteredBundleIds: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver",
    ]

    private var filteredBundleIds: Set<String> {
        Self.systemFilteredBundleIds.union(settings?.autotrackerExcludedApps ?? [])
    }

    // MARK: - Lifecycle state

    private var observers: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    init(store: AppRecordStore, settings: SettingsStore? = nil) {
        self.store = store
        self.settings = settings
        self.recordCount = store.recordCount()
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRecording else { return }
        isRecording = true

        let ws = NSWorkspace.shared.notificationCenter

        observers.append(
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                // Extract app info before crossing isolation boundary
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleId = app?.bundleIdentifier
                let name = app?.localizedName
                MainActor.assumeIsolated {
                    guard let self, let bundleId, let name else { return }
                    self.processAppChange(bundleId: bundleId, appName: name)
                }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            }
        )
        observers.append(
            ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            }
        )

        // Capture current frontmost app
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleId = app.bundleIdentifier,
           let name = app.localizedName {
            processAppChange(bundleId: bundleId, appName: name)
        }

        startPolling()
        logger.info("Recording started")
    }

    func stop() {
        flushCurrentSegment()
        stopPolling()

        let ws = NSWorkspace.shared.notificationCenter
        for token in observers {
            ws.removeObserver(token)
        }
        observers.removeAll()

        isRecording = false
        currentAppName = nil
        logger.info("Recording stopped")
    }

    // MARK: - Coalescing logic (internal for testing)

    func processAppChange(bundleId: String, appName: String) {
        guard !filteredBundleIds.contains(bundleId) else { return }

        if currentSegment == nil {
            currentSegment = Segment(bundleId: bundleId, appName: appName, startedAt: Date(), lastSeenAt: Date())
        } else if currentSegment!.bundleId == bundleId {
            currentSegment!.lastSeenAt = Date()
        } else {
            flushCurrentSegment()
            currentSegment = Segment(bundleId: bundleId, appName: appName, startedAt: Date(), lastSeenAt: Date())
        }

        currentAppName = appName
    }

    // MARK: - Private

    private func flushCurrentSegment() {
        guard let segment = currentSegment else { return }
        let now = Date()
        let duration = max(segment.lastSeenAt, now).timeIntervalSince(segment.startedAt)
        if duration > 0 {
            let record = AppRecord(
                id: nil,
                timestamp: segment.startedAt,
                appBundleId: segment.bundleId,
                appName: segment.appName,
                windowTitle: nil,
                durationSeconds: duration
            )
            store.insert(record)
        }
        recordCount = store.recordCount()
        currentSegment = nil
    }

    private func handleSleep() {
        flushCurrentSegment()
        stopPolling()
        logger.debug("Paused for sleep/session resign")
    }

    private func handleWake() {
        guard isRecording else { return }
        startPolling()
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleId = app.bundleIdentifier,
           let name = app.localizedName {
            processAppChange(bundleId: bundleId, appName: name)
        }
        logger.debug("Resumed after wake/session active")
    }

    private func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.currentSegment?.lastSeenAt = Date()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
