import XCTest
@testable import EarthCore

final class VesselTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_704_067_200)

    private func frame(type: String = "PositionReport", position: [String: Any] = [:],
                       metadata: [String: Any] = [:], removing: [String] = []) throws -> Data {
        var body: [String: Any] = ["MessageID": 1, "UserID": 368207620, "Valid": true,
                                   "Latitude": 25.7617, "Longitude": -80.1918,
                                   "Sog": 12.4, "Cog": 86.7, "TrueHeading": 87, "Timestamp": 0]
        body.merge(position) { _, new in new }
        removing.forEach { body.removeValue(forKey: $0) }
        var meta: [String: Any] = ["MMSI": 368207620, "ShipName": " @ TEST VESSEL@@ \n",
                                   "latitude": 10, "longitude": 20]
        meta.merge(metadata) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["MessageType": type, "MetaData": meta,
                                                           "Message": [type: body]])
    }

    private func sample(_ id: String = "368207620", latitude: Double = 0, longitude: Double = 0,
                        received: Date? = nil, reported: Date? = nil) -> VesselSample {
        .init(mmsi: id, name: nil, coordinate: .init(latitude: latitude, longitude: longitude),
              speedKnots: nil, courseDegrees: nil, headingDegrees: nil,
              receivedAt: received ?? now, reportedAt: reported)
    }

    func testAllThreeReportTypesUseBodyPositionAndTrimNames() throws {
        for type in ["PositionReport", "StandardClassBPositionReport", "ExtendedClassBPositionReport"] {
            let result = try XCTUnwrap(AISParser.parse(frame(type: type), receivedAt: now))
            XCTAssertEqual(result.mmsi, "368207620")
            XCTAssertEqual(result.name, "TEST VESSEL")
            XCTAssertEqual(result.coordinate, .init(latitude: 25.7617, longitude: -80.1918))
            XCTAssertEqual(result.speedKnots, 12.4)
            XCTAssertEqual(result.courseDegrees, 86.7)
            XCTAssertEqual(result.headingDegrees, 87)
            XCTAssertEqual(result.receivedAt, now)
            XCTAssertNil(result.reportedAt)
        }
    }

    func testNonPositionMessagesAndSubscriptionConfirmationAreIgnored() throws {
        for json in [#"{"MessageType":"ShipStaticData","Message":{}}"#,
                     #"{"MessageType":"SubscriptionConfirmation","Message":{"CompressionEnabled":true}}"#] {
            XCTAssertNil(try AISParser.parse(Data(json.utf8), receivedAt: now))
        }
    }

    func testMalformedAndServiceErrorFramesExposeOnlySafeErrors() {
        for json in ["{", "[]", "{}", #"{"error":"secret-api-key"}"#,
                     #"{"Error":"secret-api-key"}"#,
                     #"{"MessageType":"Error","Message":{"error":"secret-api-key"}}"#] {
            XCTAssertThrowsError(try AISParser.parse(Data(json.utf8), receivedAt: now)) { error in
                XCTAssertTrue(error is AISParseError)
                XCTAssertFalse(String(describing: error).contains("secret-api-key"))
            }
        }
    }

    func testServiceRejectionIsDistinguishedFromMalformedFramesWithoutProviderText() {
        for json in [#"{"error":"secret-api-key"}"#, #"{"MessageType":"Error","Message":"secret-api-key"}"#] {
            XCTAssertThrowsError(try AISParser.parse(Data(json.utf8), receivedAt: now)) { error in
                XCTAssertEqual(error as? AISParseError, .serviceRejected)
            }
        }
        XCTAssertThrowsError(try AISParser.parse(Data("{".utf8), receivedAt: now)) { error in
            XCTAssertEqual(error as? AISParseError, .malformedFrame)
        }
    }

    func testInvalidOrMissingBodyCoordinatesNeverUseMetadataFallback() throws {
        for body: [String: Any] in [["Latitude": 91], ["Longitude": 181], ["Latitude": -91],
                                    ["Longitude": -181], ["Valid": false]] {
            XCTAssertNil(try AISParser.parse(frame(position: body), receivedAt: now))
        }
        for removed in [["Latitude"], ["Longitude"], ["Latitude", "Longitude"], ["Valid"]] {
            XCTAssertNil(try AISParser.parse(frame(removing: removed), receivedAt: now))
        }
        XCTAssertNotNil(try AISParser.parse(frame(position: ["Latitude": 0, "Longitude": 0]), receivedAt: now))
    }

    func testMMSIRequiresNineASCIIDigitsAndMatchingBodyIdentity() throws {
        for value: Any in [123, "12345678", "1234567890", "12345678X", "１２３４５６７８９", true] {
            let data = try frame(position: ["UserID": value], metadata: ["MMSI": value])
            XCTAssertNil(try AISParser.parse(data, receivedAt: now))
        }
        XCTAssertNil(try AISParser.parse(frame(position: ["UserID": 123456789]), receivedAt: now))
        XCTAssertNil(try AISParser.parse(frame(removing: ["UserID"]), receivedAt: now))
        let leadingZero = try frame(position: ["UserID": "012345678"], metadata: ["MMSI": "012345678"])
        XCTAssertEqual(try AISParser.parse(leadingZero, receivedAt: now)?.mmsi, "012345678")
    }

    func testSentinelAndOutOfRangeMotionValuesRemainUnknown() throws {
        for body: [String: Any] in [["Sog": 102.3, "Cog": 360, "TrueHeading": 511],
                                    ["Sog": -1, "Cog": -1, "TrueHeading": -1],
                                    ["Sog": 999, "Cog": 361, "TrueHeading": 360]] {
            let result = try XCTUnwrap(AISParser.parse(frame(position: body), receivedAt: now))
            XCTAssertNil(result.speedKnots)
            XCTAssertNil(result.courseDegrees)
            XCTAssertNil(result.headingDegrees)
        }
        let zero = try XCTUnwrap(AISParser.parse(frame(position: ["Sog": 0, "Cog": 0, "TrueHeading": 0],
                                                     metadata: ["ShipName": " @@ "]), receivedAt: now))
        XCTAssertEqual(zero.speedKnots, 0)
        XCTAssertEqual(zero.courseDegrees, 0)
        XCTAssertEqual(zero.headingDegrees, 0)
        XCTAssertNil(zero.name)
    }

    func testReportedTimeAcceptsISOUTCAndAISStreamGoTimestamp() throws {
        for stamp in ["2024-01-01T00:00:00Z", "2024-01-01T00:00:00.000Z",
                      "2024-01-01 00:00:00 +0000 UTC", "2024-01-01 00:00:00.000000000 +0000 UTC"] {
            let result = try XCTUnwrap(AISParser.parse(frame(metadata: ["time_utc": stamp]), receivedAt: now))
            XCTAssertEqual(result.reportedAt, now, stamp)
        }
    }

    func testOldFutureAndMalformedReportedTimesCannotBecomeFreshPositions() throws {
        for stamp in ["2023-12-31T23:44:59Z", "2024-01-01T00:01:01Z", "not-a-date", ""] {
            XCTAssertNil(try AISParser.parse(frame(metadata: ["time_utc": stamp]), receivedAt: now), stamp)
        }
        XCTAssertNotNil(try AISParser.parse(frame(metadata: ["time_utc": "2023-12-31T23:45:00Z"]), receivedAt: now))
    }

    func testInventoryExpiresAtBothPublicReadBoundariesAndClearRemovesPositions() {
        var inventory = VesselInventory()
        inventory.merge(sample(), at: now)
        XCTAssertEqual(inventory.visible(at: now).count, 1)
        XCTAssertNotNil(inventory.sample(mmsi: "368207620", at: now.addingTimeInterval(900)))
        XCTAssertNil(inventory.sample(mmsi: "368207620", at: now.addingTimeInterval(901)))
        XCTAssertTrue(inventory.visible(at: now.addingTimeInterval(901)).isEmpty)
        inventory.clear()
        XCTAssertNil(inventory.sample(mmsi: "368207620", at: now))
        XCTAssertTrue(inventory.visible(at: now).isEmpty)
    }

    func testInventoryRejectsInvalidStaleAndFutureSamplesEvenOutsideParser() {
        var inventory = VesselInventory()
        for value in [sample("bad"), sample(latitude: .nan), sample(longitude: 181),
                      sample(received: now.addingTimeInterval(-901)), sample(received: now.addingTimeInterval(61)),
                      sample(reported: now.addingTimeInterval(-901)), sample(reported: now.addingTimeInterval(61))] {
            inventory.merge(value, at: now)
        }
        XCTAssertTrue(inventory.visible(at: now).isEmpty)
        XCTAssertNil(inventory.sample(mmsi: "368207620", at: now))
    }

    func testInventoryUsesReportTimeForOrderingAndTTLInsteadOfDelayedReceipt() {
        var inventory = VesselInventory()
        inventory.merge(sample(latitude: 30, reported: now.addingTimeInterval(-10)), at: now)
        inventory.merge(sample(latitude: 40, received: now.addingTimeInterval(1),
                               reported: now.addingTimeInterval(-20)), at: now.addingTimeInterval(1))
        XCTAssertEqual(inventory.sample(mmsi: "368207620", at: now)?.coordinate.latitude, 30)
        XCTAssertNil(inventory.sample(mmsi: "368207620", at: now.addingTimeInterval(891)))
        XCTAssertTrue(inventory.visible(at: now.addingTimeInterval(891)).isEmpty)
    }

    func testInventoryIgnoresOutOfOrderReceiptsWhenReportTimeIsAbsent() {
        var inventory = VesselInventory()
        inventory.merge(sample(latitude: 20), at: now)
        inventory.merge(sample(latitude: 40, received: now.addingTimeInterval(-1)), at: now)
        XCTAssertEqual(inventory.sample(mmsi: "368207620", at: now)?.coordinate.latitude, 20)
        inventory.merge(sample(latitude: 50, received: now.addingTimeInterval(1)), at: now.addingTimeInterval(1))
        XCTAssertEqual(inventory.sample(mmsi: "368207620", at: now.addingTimeInterval(1))?.coordinate.latitude, 50)
    }

    func testInventoryBoundsStorageAndKeepsNewestVessels() {
        var inventory = VesselInventory()
        for index in 0..<2_010 {
            inventory.merge(sample(String(100_000_000 + index), received: now.addingTimeInterval(Double(index) / 10)),
                            at: now.addingTimeInterval(Double(index) / 10))
        }
        let end = now.addingTimeInterval(201)
        XCTAssertNil(inventory.sample(mmsi: "100000000", at: end))
        XCTAssertNotNil(inventory.sample(mmsi: "100002009", at: end))
        let retained = (0..<2_010).filter { inventory.sample(mmsi: String(100_000_000 + $0), at: end) != nil }
        XCTAssertEqual(retained.count, 2_000)
    }

    func testDenseEuropeanWatersLeaveSpaceWithoutMovingOrDeletingObservations() {
        var inventory = VesselInventory()
        var values: [VesselSample] = []
        for latitude in stride(from: 36.0, through: 66.0, by: 6) {
            for longitude in stride(from: -12.0, through: 30.0, by: 6) {
                values.append(sample(String(100000000 + values.count), latitude: latitude, longitude: longitude))
            }
        }
        for value in values { inventory.merge(value, at: now) }
        let visible = inventory.visible(at: now)
        XCTAssertGreaterThan(visible.count, 1)
        XCTAssertLessThanOrEqual(visible.count, 6, "Europe should contain scattered accents, not a fleet of icons")
        for (index, vessel) in visible.enumerated() {
            XCTAssertEqual(vessel, values.first { $0.mmsi == vessel.mmsi })
            for other in visible.dropFirst(index + 1) {
                XCTAssertGreaterThanOrEqual(vessel.coordinate.distance(to: other.coordinate), 15)
            }
        }
        for value in values { XCTAssertEqual(inventory.sample(mmsi: value.mmsi, at: now), value) }
        // Refreshes must not randomly swap the representative boat in each region.
        for value in values.reversed() { inventory.merge(value, at: now) }
        XCTAssertEqual(inventory.visible(at: now), visible)
    }

    func testGlobalDecorativeSelectionHasBoundedDensity() {
        var inventory = VesselInventory()
        var id = 100000000
        for latitude in stride(from: -75.0, through: 75.0, by: 15) {
            for longitude in stride(from: -180.0, to: 180.0, by: 15) {
                inventory.merge(sample(String(id), latitude: latitude, longitude: longitude), at: now)
                id += 1
            }
        }
        XCTAssertEqual(inventory.visible(at: now).count, 28)
    }

    func testVisibleSelectionIsSparseDeterministicAndHandlesDatelineAndPoles() {
        let values = [sample("100000001", latitude: 0, longitude: 179),
                      sample("100000002", latitude: 0, longitude: -179),
                      sample("100000003", latitude: 89, longitude: 0),
                      sample("100000004", latitude: 89, longitude: 180),
                      sample("100000005", latitude: 0, longitude: 90)]
        var first = VesselInventory(), second = VesselInventory()
        for value in values { first.merge(value, at: now) }
        for value in values.reversed() { second.merge(value, at: now) }
        XCTAssertEqual(first.visible(at: now), second.visible(at: now))
        XCTAssertEqual(first.visible(at: now).map(\.mmsi), ["100000001", "100000003", "100000005"])
        XCTAssertEqual(first.visible(at: now, limit: 2).count, 2)
        XCTAssertTrue(first.visible(at: now, limit: 0).isEmpty)
        XCTAssertTrue(first.visible(at: now, limit: -1).isEmpty)
        XCTAssertNotNil(first.sample(mmsi: "100000002", at: now), "Sparse rendering must not erase vessel data")
    }
}
