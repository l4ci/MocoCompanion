import Foundation
import os

/// Centralized file-based logger for MocoCompanion.
/// Writes structured log entries to separate files for API and App logs.
/// Thread-safe via actor isolation.
actor AppLogger {
    static let shared = AppLogger()

    enum LogLevel: Int, Comparable, CaseIterable, Codable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        var label: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERROR"
            }
        }

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum LogCategory: String {
        case api = "api"
        case app = "app"
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private let maxFileSize: Int = 2 * 1024 * 1024  // 2 MB per log file
    private let maxBackups = 3

    // MARK: - Log directory

    private var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MocoCompanion/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var apiLogPath: URL { logDirectory.appendingPathComponent("moco-api.log") }
    var appLogPath: URL { logDirectory.appendingPathComponent("moco-app.log") }

    private func logPath(for category: LogCategory) -> URL {
        switch category {
        case .api: return apiLogPath
        case .app: return appLogPath
        }
    }

    // MARK: - Public API

    func api(_ message: String, level: LogLevel = .info, context: String? = nil) {
        write(category: .api, level: level, message: message, context: context)
    }

    func app(_ message: String, level: LogLevel = .info, context: String? = nil) {
        write(category: .app, level: level, message: message, context: context)
    }

    // MARK: - Convenience

    func apiRequest(method: String, url: String, statusCode: Int? = nil, duration: TimeInterval? = nil, error: String? = nil) {
        var parts = ["\(method) \(url)"]
        if let code = statusCode { parts.append("→ \(code)") }
        if let dur = duration { parts.append(String(format: "%.0fms", dur * 1000)) }
        if let err = error { parts.append("ERROR: \(err)") }
        let level: LogLevel = error != nil ? .error : (statusCode.map { $0 >= 400 } ?? false) ? .warning : .info
        write(category: .api, level: level, message: parts.joined(separator: " "))
    }

    // MARK: - File management

    func clearLog(_ category: LogCategory) {
        let path = logPath(for: category)
        try? FileManager.default.removeItem(at: path)
    }

    func logSize(_ category: LogCategory) -> Int {
        let path = logPath(for: category)
        return (try? FileManager.default.attributesOfItem(atPath: path.path))?[.size] as? Int ?? 0
    }

    // MARK: - Log Level Filtering

    var apiLogLevel: LogLevel = .info
    var appLogLevel: LogLevel = .info

    func updateLogLevels(api: LogLevel, app: LogLevel) {
        apiLogLevel = api
        appLogLevel = app
    }

    // MARK: - Buffered Writing

    /// Buffer for log lines. Flushed every 30 seconds or when 10 lines accumulate.
    /// The 30s cadence keeps logs fresh enough for post-mortem debugging while
    /// not waking the writer thread every 5s in the steady state. The 10-line
    /// threshold still keeps bursty log events timely.
    private var apiBuffer: [String] = []
    private var appBuffer: [String] = []
    private var flushTask: Task<Void, Never>?
    private static let flushThreshold = 10
    private static let flushInterval: Duration = .seconds(30)

    private func write(category: LogCategory, level: LogLevel, message: String, context: String? = nil) {
        let minLevel = category == .api ? apiLogLevel : appLogLevel
        guard level >= minLevel else { return }

        let timestamp = dateFormatter.string(from: Date())
        var line = "[\(timestamp)] [\(level.label)]"
        if let ctx = context { line += " [\(ctx)]" }
        line += " \(message)\n"

        switch category {
        case .api: apiBuffer.append(line)
        case .app: appBuffer.append(line)
        }

        // Flush if buffer is full
        if apiBuffer.count >= Self.flushThreshold || appBuffer.count >= Self.flushThreshold {
            flushBuffers()
        }

        // Schedule periodic flush if not already scheduled
        if flushTask == nil {
            flushTask = Task {
                try? await Task.sleep(for: Self.flushInterval)
                self.flushBuffers()
                self.clearFlushTask()
            }
        }
    }

    private func clearFlushTask() {
        flushTask = nil
    }

    /// Write buffered lines to disk.
    private func flushBuffers() {
        if !apiBuffer.isEmpty {
            let lines = apiBuffer.joined()
            apiBuffer.removeAll()
            writeToFile(lines, path: logPath(for: .api))
        }
        if !appBuffer.isEmpty {
            let lines = appBuffer.joined()
            appBuffer.removeAll()
            writeToFile(lines, path: logPath(for: .app))
        }
    }

    private func writeToFile(_ content: String, path: URL) {
        rotateIfNeeded(path: path)
        guard let data = content.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: path.path) {
            if let handle = try? FileHandle(forWritingTo: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: path)
        }
    }

    private func rotateIfNeeded(path: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? Int,
              size > maxFileSize else { return }

        let dir = path.deletingLastPathComponent()
        let name = path.deletingPathExtension().lastPathComponent
        let ext = path.pathExtension

        // Rotate: .3 → delete, .2 → .3, .1 → .2, current → .1
        for i in stride(from: maxBackups, through: 1, by: -1) {
            let src = dir.appendingPathComponent("\(name).\(i).\(ext)")
            if i == maxBackups {
                try? FileManager.default.removeItem(at: src)
            } else {
                let dst = dir.appendingPathComponent("\(name).\(i + 1).\(ext)")
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
        let first = dir.appendingPathComponent("\(name).1.\(ext)")
        try? FileManager.default.moveItem(at: path, to: first)
    }
}
