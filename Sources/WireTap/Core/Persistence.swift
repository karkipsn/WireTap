import Foundation
import os

// MARK: - WireTapStorage (TRACER-001)

/// Where WireTap keeps captured entries.
///
/// - `.inMemory` (default): entries live only in memory and are lost on relaunch —
///   today's behavior, zero IO.
/// - `.disk`: entries are additionally appended to a rolling JSONL file per stream
///   and reloaded on next launch. DEBUG-oriented; off by default.
public enum WireTapStorage: Sendable {
    case inMemory
    case disk(directory: URL? = nil, fileCap: Int = 5_000)
}

/// Identifier prefix for this library's diagnostic plumbing (Logger subsystem,
/// dispatch-queue labels). Package-neutral on purpose — WireTap embeds in any app,
/// so it must not carry a consumer app's reverse-DNS.
let wiretapIdentifier = "wiretap"

let wiretapLog = Logger(subsystem: wiretapIdentifier, category: "persistence")

// MARK: - PersistenceWriter

/// Appends `Codable` entries to a newline-delimited JSON file, off the main actor,
/// with a rolling line cap. One instance per stream file.
///
/// All mutation happens on a private serial queue, so callers never block on disk IO.
/// `@unchecked Sendable`: every mutable member is touched only inside `queue` blocks
/// (or in `init`/`loadAll`, which run before any append is enqueued).
final class PersistenceWriter<Entry: Codable & Sendable>: @unchecked Sendable {

    private let fileURL: URL
    private let cap: Int
    private let queue: DispatchQueue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var handle: FileHandle?
    private var lineCount = 0

    /// Fails (returns nil) when the directory/file cannot be created — caller then
    /// stays in-memory.
    init?(fileURL: URL, cap: Int) {
        self.fileURL = fileURL
        self.cap = max(1, cap)
        self.queue = DispatchQueue(label: "\(wiretapIdentifier).persist.\(fileURL.lastPathComponent)")

        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
        } catch {
            wiretapLog.error("disk persistence unavailable for \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.lineCount = Self.countLines(at: fileURL)
    }

    /// Decode every line, skipping (and counting) any that fail. Called once at attach
    /// time, before any append is enqueued.
    func loadAll() -> (items: [Entry], skipped: Int) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return ([], 0) }
        var items: [Entry] = []
        var skipped = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: data) else {
                skipped += 1
                continue
            }
            items.append(entry)
        }
        return (items, skipped)
    }

    /// Enqueue an append. Returns immediately; the write happens on the serial queue.
    func append(_ entry: Entry) {
        queue.async { [weak self] in
            guard let self, let line = try? self.encoder.encode(entry) else { return }
            self.openHandleIfNeeded()
            guard let handle = self.handle else { return }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.write(contentsOf: Data([0x0a]))
                self.lineCount += 1
                if self.lineCount > self.cap { self.compact() }
            } catch {
                wiretapLog.error("append failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Empty the file (used by `clear()`).
    func truncate() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.handle?.close()
            self.handle = nil
            try? Data().write(to: self.fileURL)
            self.lineCount = 0
        }
    }

    /// Block until all enqueued writes have completed. Test-only / shutdown use.
    func flush() {
        queue.sync {}
    }

    // MARK: Private

    private func openHandleIfNeeded() {
        if handle == nil { handle = try? FileHandle(forWritingTo: fileURL) }
    }

    /// Rewrite the file keeping only the newest `cap` lines. Runs on the queue.
    private func compact() {
        try? handle?.close()
        handle = nil
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > cap else { lineCount = lines.count; return }
        let kept = lines.suffix(cap).joined(separator: "\n") + "\n"
        try? kept.write(to: fileURL, atomically: true, encoding: .utf8)
        lineCount = cap
    }

    private static func countLines(at url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }
}

