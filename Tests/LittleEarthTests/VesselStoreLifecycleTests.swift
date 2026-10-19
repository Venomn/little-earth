import XCTest
import Foundation
@testable import LittleEarth

private actor GatedCloseAISConnection: AISConnection {
    private var pending: CheckedContinuation<Data, Error>?
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdsClose: Bool
    private(set) var closeStarted = false
    private(set) var completedCloses = 0
    private(set) var closed = false

    init(holdsClose: Bool = false) { self.holdsClose = holdsClose }
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data {
        if closed { throw CancellationError() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func ping() async throws {}
    func close() async {
        closeStarted = true
        if holdsClose { await withCheckedContinuation { closeWaiters.append($0) } }
        closed = true
        completedCloses += 1
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
    func releaseClose() {
        holdsClose = false
        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    func hasReader() -> Bool { pending != nil }
    func yield(_ text: String) {
        pending?.resume(returning: Data(text.utf8))
        pending = nil
    }
}

@MainActor final class VesselStoreLifecycleTests: XCTestCase {
    private func waitUntil(_ predicate: () async -> Bool) async throws -> Bool {
        for _ in 0..<1_000 {
            if await predicate() { return true }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func testRejectedOldConnectionCannotEraseReplacementConnectionDuringAwaitedClose() async throws {
        let oldConnection = GatedCloseAISConnection(holdsClose: true)
        let replacement = GatedCloseAISConnection()
        var connections = 0
        let store = VesselStore(connectionFactory: {
            connections += 1
            return connections == 1 ? oldConnection : replacement
        })
        store.configure(key: "old-test-fixture-key")
        store.setActive(true)
        let firstReady = try await waitUntil { await oldConnection.hasReader() }
        XCTAssertTrue(firstReady)
        await oldConnection.yield(#"{"error":"test rejection"}"#)
        let closingOld = try await waitUntil { await oldConnection.closeStarted }
        XCTAssertTrue(closingOld)
        XCTAssertEqual(store.state, .rejected)

        // Reconfiguration runs while the rejected generation is suspended in close().
        store.configure(key: "new-test-fixture-key")
        let replacementReady = try await waitUntil { await replacement.hasReader() }
        XCTAssertTrue(replacementReady)
        XCTAssertEqual(connections, 2)
        await replacement.yield(#"{"MessageType":"SubscriptionConfirmation","Message":{"CompressionEnabled":true}}"#)
        let connected = try await waitUntil { store.state == .connected }
        XCTAssertTrue(connected)

        await oldConnection.releaseClose()
        let oldCloseCompleted = try await waitUntil { await oldConnection.completedCloses > 0 }
        XCTAssertTrue(oldCloseCompleted)
        // Let both the rejected receive loop and its cancelled keepalive unwind.
        for _ in 0..<10 { await Task.yield() }
        store.setActive(false)
        let replacementClosed = try await waitUntil { await replacement.closed }
        XCTAssertTrue(replacementClosed, "A stale rejection must not discard the replacement connection handle")
        XCTAssertEqual(store.state, .paused)
        XCTAssertTrue(store.visible.isEmpty)

        // Even a failing run releases the suspended reader instead of leaking a task.
        await replacement.close()
    }
}
