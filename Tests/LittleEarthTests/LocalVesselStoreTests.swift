import XCTest
import Foundation
import EarthCore
import Darwin
@testable import LittleEarth

@MainActor final class LocalVesselStoreTests: XCTestCase {
    private func snapshot(version: Int = 1, sequence: Int = 1, ships: [VesselSample]? = nil) throws -> Data {
        let ship = VesselSample(mmsi:"990000001",name:"TEST FIXTURE",coordinate:GeoCoordinate(latitude:20,longitude:-40),speedKnots:10,courseDegrees:45,headingDegrees:45,receivedAt:Date())
        let samples = try JSONSerialization.jsonObject(with:JSONEncoder().encode(ships ?? [ship]))
        return try JSONSerialization.data(withJSONObject:["version":version,"sequence":sequence,"state":"connected","vessels":samples,"receivedFrames":2,"acceptedReports":1,"compressionEnabled":false])
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTFail("Local service did not reach expected state")
    }
    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of:"'",with:"'\\''") + "'" }

    func testPrivateBackendRestartCrashPauseAndLateCallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let script = directory.appendingPathComponent("fixture.sh"), pidFile = directory.appendingPathComponent("pid")
        let json = String(decoding:try snapshot(),as:UTF8.self)
        let lateEmpty = String(decoding:try snapshot(sequence:0,ships:[]),as:UTF8.self)
        try "printf '%s' \"$$\" > \(shellQuote(pidFile.path))\nprintf '%s\\n' \(shellQuote(json)) \(shellQuote(lateEmpty))\nexec /bin/cat\n".write(to:script,atomically:true,encoding:.utf8)
        let store = LocalVesselStore(executable:URL(fileURLWithPath:"/bin/sh"),arguments:[script.path],retryDelay:0.03)
        defer { store.setActive(false) }
        XCTAssertTrue(store.visible.isEmpty)
        store.setActive(true)
        try await waitUntil { store.state == .connected }
        XCTAssertEqual(store.visible.first?.mmsi,"990000001")
        XCTAssertEqual(store.sample(mmsi:"990000001"),store.visible.first)
        XCTAssertEqual(store.diagnostics?.acceptedReports,1)
        let firstPID = try XCTUnwrap(Int32(String(contentsOf:pidFile)))
        kill(firstPID,SIGTERM)
        try await waitUntil { store.state == .retrying }
        XCTAssertTrue(store.visible.isEmpty)
        try await waitUntil { store.state == .connected }
        let replacementPID = try XCTUnwrap(Int32(String(contentsOf:pidFile)))
        XCTAssertNotEqual(firstPID,replacementPID)
        store.reload()
        try await waitUntil { store.state == .connected }
        let reloadedPID = try XCTUnwrap(Int32(String(contentsOf:pidFile)))
        XCTAssertNotEqual(reloadedPID,replacementPID)
        store.setActive(false)
        try await waitUntil { kill(reloadedPID,0) != 0 }
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertEqual(store.state,.paused)
        XCTAssertTrue(store.visible.isEmpty)
        XCTAssertNil(store.sample(mmsi:"990000001"))
    }

    func testCredentialFailureSurvivesPipeAndReconnectRecoversWithoutStaleShips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let script = directory.appendingPathComponent("credential.sh")
        let good = String(decoding:try snapshot(),as:UTF8.self)
        let failure = good.replacingOccurrences(of:"connected",with:"credentialUnavailable")
        let decoded = try JSONDecoder().decode(VesselServiceSnapshot.self,from:Data(failure.utf8))
        XCTAssertEqual(decoded.state,.credentialUnavailable)
        _ = try decoded.validated(at:Date())
        try "printf '%s\\n' \(shellQuote(failure))\nexec /bin/cat\n".write(to:script,atomically:true,encoding:.utf8)
        let store = LocalVesselStore(executable:URL(fileURLWithPath:"/bin/sh"),arguments:[script.path])
        defer { store.setActive(false) }
        store.setActive(true)
        try await waitUntil { store.state == .credentialUnavailable }
        XCTAssertTrue(store.visible.isEmpty)
        XCTAssertNil(store.sample(mmsi:"990000001"))
        for language in AppLanguage.allCases {
            XCTAssertEqual(store.statusText(in:language),L10n(language).text(.shipsKeyUnavailable))
        }
        try "printf '%s\\n' \(shellQuote(good))\nexec /bin/cat\n".write(to:script,atomically:true,encoding:.utf8)
        store.authorizeSavedKey()
        try await waitUntil { store.state == .connected }
        XCTAssertEqual(store.visible.count,1)
    }

    func testMalformedBackendFailsClosedAndDoesNotSurvivePause() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let script = directory.appendingPathComponent("bad.sh")
        try "printf '%s\\n' '{not-json}'\nexec /bin/cat\n".write(to:script,atomically:true,encoding:.utf8)
        let store = LocalVesselStore(executable:URL(fileURLWithPath:"/bin/sh"),arguments:[script.path],retryDelay:1)
        defer { store.setActive(false) }
        store.setActive(true)
        try await waitUntil { store.state == .retrying }
        XCTAssertTrue(store.visible.isEmpty)
        store.setActive(false)
        XCTAssertEqual(store.state,.paused)
    }

    func testPipeFramingVersionAndFreshnessBoundaries() throws {
        let data = try snapshot()
        var parser = VesselServiceFrames()
        XCTAssertTrue(try parser.append(data.prefix(23)).isEmpty)
        var tail = Data(data.dropFirst(23)); tail.append(10); tail.append(data); tail.append(10)
        let frames = try parser.append(tail)
        XCTAssertEqual(frames,[data,data])
        XCTAssertEqual(try JSONDecoder().decode(VesselServiceSnapshot.self,from:frames[0]).validated(at:Date()).count,1)
        XCTAssertThrowsError(try JSONDecoder().decode(VesselServiceSnapshot.self,from:snapshot(version:99)).validated(at:Date()))
        let stale = VesselSample(mmsi:"990000002",name:nil,coordinate:GeoCoordinate(latitude:0,longitude:0),speedKnots:nil,courseDegrees:nil,headingDegrees:nil,receivedAt:Date(timeIntervalSinceNow:-1000))
        XCTAssertTrue(try JSONDecoder().decode(VesselServiceSnapshot.self,from:snapshot(ships:[stale])).validated(at:Date()).isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(VesselServiceSnapshot.self,from:snapshot(ships:[stale,stale])).validated(at:Date()))
        var oversized = VesselServiceFrames()
        XCTAssertThrowsError(try oversized.append(Data(repeating:65,count:65_537)))
    }
}
