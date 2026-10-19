import XCTest
import Foundation
@testable import LittleEarth

private actor TestAISConnection: AISConnection {
    var sent = [Data]()
    var closed = false
    private var pending: CheckedContinuation<Data,Error>?
    func send(_ data: Data) async throws { sent.append(data) }
    func receive() async throws -> Data {
        if closed { throw CancellationError() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func ping() async throws {}
    func close() async { closed = true; pending?.resume(throwing:CancellationError()); pending = nil }
    func yield(_ text: String) { pending?.resume(returning:Data(text.utf8)); pending = nil }
    func hasReader() -> Bool { pending != nil }
    func sendCount() -> Int { sent.count }
}

@MainActor final class VesselStoreTests: XCTestCase {
    func testUnreadableKeyStopsConnectionAndCanBeReconfigured() async throws {
        let connection = TestAISConnection()
        var connections = 0
        let store = VesselStore(connectionFactory:{ connections += 1; return connection })
        store.setActive(true)
        store.beginCredentialRead()
        XCTAssertEqual(store.state,.connecting)
        store.credentialReadFailed()
        XCTAssertEqual(store.state,.credentialUnavailable)
        XCTAssertEqual(connections,0)
        XCTAssertFalse(store.configured)
        XCTAssertTrue(store.visible.isEmpty)
        store.configure(key:"test-fixture-key")
        for _ in 0..<100 where !(await connection.hasReader()) { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(connections,1)
        XCTAssertEqual(store.state,.connecting)
        store.setActive(false)
    }
    func testNoKeyMakesNoConnectionAndDisableClearsAndCloses() async throws {
        let connection = TestAISConnection()
        var connections = 0
        let store = VesselStore(connectionFactory:{ connections += 1; return connection })
        store.setActive(true)
        XCTAssertEqual(connections,0)
        XCTAssertEqual(store.state,.unconfigured)
        store.configure(key:"test-fixture-key")
        for _ in 0..<100 where !(await connection.hasReader()) { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(connections,1)
        let sent = await connection.sendCount()
        XCTAssertEqual(sent,1)
        await connection.yield("{\"MessageType\":\"SubscriptionConfirmation\",\"Message\":{\"CompressionEnabled\":true}}")
        for _ in 0..<100 where store.state != .connected { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(store.state,.connected)
        store.configure(key:nil)
        for _ in 0..<100 where !(await connection.closed) { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(store.state,.unconfigured)
        XCTAssertTrue(store.visible.isEmpty)
        let closed = await connection.closed
        XCTAssertTrue(closed)
        store.setActive(false)
    }
    func testSilentSubscriptionTimesOutAndCanBeStopped() async throws {
        let connection = TestAISConnection()
        let store = VesselStore(confirmationTimeout:0.02,connectionFactory:{ connection })
        store.configure(key:"test-fixture-key"); store.setActive(true)
        for _ in 0..<200 where store.state != .retrying { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(store.state,.retrying)
        let closed = await connection.closed
        XCTAssertTrue(closed)
        store.setActive(false)
        XCTAssertEqual(store.state,.paused)
    }
    func testRejectedSubscriptionDoesNotPretendToBeConnectedOrRetry() async throws {
        let connection = TestAISConnection()
        var connections = 0
        let store = VesselStore(connectionFactory:{ connections += 1; return connection })
        store.configure(key:"test-fixture-key"); store.setActive(true)
        for _ in 0..<100 where !(await connection.hasReader()) { try await Task.sleep(nanoseconds:1_000_000) }
        await connection.yield("{\"error\":\"Invalid API key\"}")
        for _ in 0..<100 where store.state != .rejected { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertEqual(store.state,.rejected)
        XCTAssertEqual(connections,1)
        XCTAssertTrue(store.visible.isEmpty)
        store.setActive(false)
    }
}
