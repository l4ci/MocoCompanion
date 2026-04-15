import Foundation
import os

/// Thread-safe ring buffer recording internal diagnostic events.
/// Each entry is also appended to `breadcrumbs.log` for crash survival.
/// Gated by `isEnabled` — toggle via Debug settings tab.
final class BreadcrumbTrail: @unchecked Sendable {
    static let shared = BreadcrumbTrail()

    struct Entry: Sendable {
        let timestamp: Date
        let subsystem: String
        let event: String
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []
    private let capacity = 200
    private var writeIndex = 0
    private var lineCount = 0
    private var fileHandle: FileHandle?
    private(set) var isEnabled = false

    private let filePath: URL
    private let logger = Logger(category: "Breadcrumbs")

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let appSupport = URL.applicationSupportDirectory
        let logDir = appSupport.appendingPathComponent("MocoCompanion/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        filePath = logDir.appendingPathComponent("breadcrumbs.log")
        buffer.reserveCapacity(capacity)
    }

    // MARK: - Enable / Disable

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled
        if enabled {
            openFile()
            logger.info("Breadcrumb trail enabled")
        } else {
            logger.info("Breadcrumb trail disabled")
            closeFile()
        }
    }

    // MARK: - Record

    /// Record a breadcrumb. No-op when disabled. Safe to call from any thread.
    func record(_ subsystem: String, _ event: String) {
        lock.lock()
        defer { lock.unlock() }
        guard isEnabled else { return }

        let entry = Entry(timestamp: Date(), subsystem: subsystem, event: event)

        // Ring buffer insert
        if buffer.count < capacity {
            buffer.append(entry)
        } else {
            buffer[writeIndex] = entry
        }
        writeIndex = (writeIndex + 1) % capacity
        lineCount += 1

        // Append to file for crash survival
        appendToFile(entry)

        // Compact the file periodically to prevent unbounded growth
        if lineCount > capacity * 3 {
            rewriteFile()
        }
    }

    // MARK: - Read

    /// Returns all entries in chronological order.
    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.count == capacity else { return buffer }
        return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
    }

    /// Number of entries currently in the ring buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    // MARK: - Clear

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        writeIndex = 0
        lineCount = 0
        truncateFile()
    }

    // MARK: - File Path (for UI)

    var logFileURL: URL { filePath }

    // MARK: - File I/O (must be called under lock)

    private func openFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: filePath.path) {
            fm.createFile(atPath: filePath.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: filePath)
        fileHandle?.seekToEndOfFile()
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func appendToFile(_ entry: Entry) {
        guard let fh = fileHandle else { return }
        let ts = dateFormatter.string(from: entry.timestamp)
        let line = "[\(ts)] [\(entry.subsystem)] \(entry.event)\n"
        guard let data = line.data(using: .utf8) else { return }
        fh.write(data)
        // Synchronize to ensure crash survival — key difference from buffered AppLogger
        try? fh.synchronize()
    }

    private func truncateFile() {
        try? fileHandle?.seek(toOffset: 0)
        try? fileHandle?.truncate(atOffset: 0)
    }

    /// Rewrite the file with only the current ring buffer contents to prevent unbounded growth.
    private func rewriteFile() {
        closeFile()
        let entries = buffer.count < capacity
            ? buffer
            : Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
        var content = ""
        for entry in entries {
            let ts = dateFormatter.string(from: entry.timestamp)
            content += "[\(ts)] [\(entry.subsystem)] \(entry.event)\n"
        }
        try? content.write(to: filePath, atomically: true, encoding: .utf8)
        fileHandle = try? FileHandle(forWritingTo: filePath)
        fileHandle?.seekToEndOfFile()
        lineCount = entries.count
    }
}
