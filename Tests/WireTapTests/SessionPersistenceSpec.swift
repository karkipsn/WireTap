import XCTest
@testable import WireTap

/// TRACER-001 — Session Persistence.
///
/// Each test maps 1:1 to an acceptance criterion in
/// `doc/specs/TRACER-001-session-persistence.md`. Disk tests use a fresh temp
/// directory (and fresh store instances to simulate relaunch) so they never touch
/// the real Application Support directory and never bleed across tests.
@MainActor
final class SessionPersistenceSpec: XCTestCase {

    private var tmp: URL!

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiretap-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        tmp = nil
    }

    private func url(_ name: String) -> URL { tmp.appendingPathComponent(name) }
    private func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }
    private func lineCount(_ name: String) throws -> Int {
        let text = try String(contentsOf: url(name), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    // MARK: AC-1 — default stays in-memory, no disk IO

    func test_AC1_defaultIsInMemory_noDiskIO() throws {
        let store = NetworkStore() // not disk-enabled
        store.record(NetworkEntry(method: "GET", url: "https://x.com", durationMs: 1))
        store.flushPersistenceForTesting()

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertFalse(fileExists("network.jsonl"), "no file should be written when persistence is off")
    }

    // MARK: AC-2 — entries survive a simulated relaunch

    func test_AC2_entriesReloadAfterRelaunch() throws {
        // First "launch"
        let net = NetworkStore(); net.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 1000)
        let ble = BleStore();     ble.enableDiskPersistence(fileURL: url("ble.jsonl"), fileCap: 1000)
        let nfc = NfcStore();     nfc.enableDiskPersistence(fileURL: url("nfc.jsonl"), fileCap: 1000)

        net.record(NetworkEntry(method: "GET", url: "https://a", durationMs: 1))
        net.record(NetworkEntry(method: "POST", url: "https://b", durationMs: 2))
        net.record(NetworkEntry(method: "PUT", url: "https://c", durationMs: 3))
        ble.log(BleEntry(type: .connected, device: "MS2"))
        ble.log(BleEntry(type: .disconnected, device: "MS2", error: "dropped"))
        nfc.log(NfcEntry(type: .scanCompleted, detail: "ok"))
        net.flushPersistenceForTesting(); ble.flushPersistenceForTesting(); nfc.flushPersistenceForTesting()

        // Second "launch" — new stores, same files
        let net2 = NetworkStore(); net2.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 1000)
        let ble2 = BleStore();     ble2.enableDiskPersistence(fileURL: url("ble.jsonl"), fileCap: 1000)
        let nfc2 = NfcStore();     nfc2.enableDiskPersistence(fileURL: url("nfc.jsonl"), fileCap: 1000)

        XCTAssertEqual(net2.entries.count, 3)
        XCTAssertEqual(ble2.entries.count, 2)
        XCTAssertEqual(nfc2.entries.count, 1)
        // newest first
        XCTAssertEqual(net2.entries.first?.url, "https://c")
        XCTAssertEqual(net2.entries.last?.url, "https://a")
        XCTAssertEqual(ble2.entries.first?.type, .disconnected)
        XCTAssertEqual(ble2.entries.first?.error, "dropped")
    }

    // MARK: AC-3 — file cap rolls oldest

    func test_AC3_fileCapRollsOldest() throws {
        let net = NetworkStore(); net.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 100)
        for i in 1...150 {
            net.record(NetworkEntry(method: "GET", url: "https://x/\(i)", durationMs: i))
        }
        net.flushPersistenceForTesting()

        XCTAssertEqual(try lineCount("network.jsonl"), 100, "disk file should hold exactly the cap")

        // The 100 newest survive after relaunch
        let net2 = NetworkStore(); net2.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 100)
        let urls = net2.entries.map(\.url)
        XCTAssertEqual(net2.entries.count, 100)
        XCTAssertTrue(urls.contains("https://x/150"))
        XCTAssertFalse(urls.contains("https://x/50"))
    }

    // MARK: AC-4 — clear() truncates disk

    func test_AC4_clearTruncatesDiskFile() throws {
        let ble = BleStore(); ble.enableDiskPersistence(fileURL: url("ble.jsonl"), fileCap: 1000)
        ble.log(BleEntry(type: .connected))
        ble.log(BleEntry(type: .notification))
        ble.flushPersistenceForTesting()
        XCTAssertGreaterThan(try lineCount("ble.jsonl"), 0)

        ble.clear()
        ble.flushPersistenceForTesting()

        XCTAssertTrue(ble.entries.isEmpty)
        let size = try FileManager.default.attributesOfItem(atPath: url("ble.jsonl").path)[.size] as? Int
        XCTAssertEqual(size, 0, "file should be truncated to 0 bytes")

        let ble2 = BleStore(); ble2.enableDiskPersistence(fileURL: url("ble.jsonl"), fileCap: 1000)
        XCTAssertTrue(ble2.entries.isEmpty)
    }

    // MARK: AC-5 — redaction precedes persistence

    func test_AC5_redactedBeforeDisk() throws {
        let net = NetworkStore(); net.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 1000)
        net.record(NetworkEntry(
            method: "POST",
            url: "https://api/sessions",
            requestHeaders: ["Authorization": "Bearer super-secret-token", "Accept": "application/json"],
            durationMs: 10
        ))
        net.flushPersistenceForTesting()

        let raw = try String(contentsOf: url("network.jsonl"), encoding: .utf8)
        XCTAssertFalse(raw.contains("super-secret-token"), "secret must never reach disk")
        XCTAssertTrue(raw.contains("[redacted]"))
    }

    // MARK: AC-6 — corrupt line tolerance

    func test_AC6_corruptLineSkipped() throws {
        // Build a ble.jsonl whose 2nd line is invalid JSON.
        let good = BleEntry(type: .connected, device: "MS2")
        let line = try JSONEncoder().encode(good)
        var contents = Data()
        contents.append(line); contents.append(0x0a)
        contents.append("this is not json".data(using: .utf8)!); contents.append(0x0a)
        contents.append(line); contents.append(0x0a)
        try contents.write(to: url("ble.jsonl"))

        let ble = BleStore(); ble.enableDiskPersistence(fileURL: url("ble.jsonl"), fileCap: 1000)

        // 2 valid entries load, plus one info entry noting the skip.
        let infoEntries = ble.entries.filter { $0.type == .info }
        XCTAssertEqual(ble.entries.filter { $0.type == .connected }.count, 2)
        XCTAssertEqual(infoEntries.count, 1)
        XCTAssertTrue(infoEntries.first?.detail?.contains("1") == true,
                      "info entry should record the skipped-line count")
    }

    // MARK: AC-7 — capture does not block the main actor on disk IO

    func test_AC7_captureDoesNotAwaitDiskIO() throws {
        let net = NetworkStore(); net.enableDiskPersistence(fileURL: url("network.jsonl"), fileCap: 5000)
        let start = Date()
        for i in 1...1000 {
            net.record(NetworkEntry(method: "GET", url: "https://x/\(i)", durationMs: i))
        }
        let elapsed = Date().timeIntervalSince(start)
        // Writes are dispatched to a background queue; 1000 records must return fast.
        XCTAssertLessThan(elapsed, 1.0, "record() should not block on disk IO")

        // And everything still persists once the queue drains.
        net.flushPersistenceForTesting()
        XCTAssertEqual(try lineCount("network.jsonl"), 1000)
    }
}
