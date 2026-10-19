import XCTest
@testable import EarthCore

final class WeatherLifecycleTests: XCTestCase {
    func testInterruptedInitialFetchCanResumeAndOldCompletionCannotWin() {
        var gate = WeatherRefreshGate()
        let now = Date(timeIntervalSince1970:1800000000)
        let old = gate.begin(at:now)!
        gate.cancel()
        let resumed = gate.begin(at:now.addingTimeInterval(1))
        XCTAssertNotNil(resumed)
        XCTAssertFalse(gate.complete(old))
        XCTAssertTrue(gate.isLoading)
        XCTAssertTrue(gate.complete(resumed!))
        XCTAssertNil(gate.begin(at:now.addingTimeInterval(2)))
    }
    func testMissingRegionIsUnknownInBothCloudProjectionAndDetails() throws {
        let helper = WeatherTests(), point = GeoCoordinate(latitude:0,longitude:0)
        let neighbor = try WeatherParser.parse(Data(helper.row(lat:0,lon:15).utf8),requested:[.init(latitude:0,longitude:15)],fetchedAt:helper.now)
        let projection = RegionalWeather(samples:neighbor,at:helper.now)
        XCTAssertNil(projection.nearest(to:point))
        XCTAssertNil(projection.cloudCover(at:point))
        XCTAssertEqual(projection.cloudCover(at:.init(latitude:0,longitude:15))!,80,accuracy:0.001)
    }
    func testSuccessfulHTTPWithMissingValuesIsNotACompleteRefresh() throws {
        let helper = WeatherTests(), requested = [GeoCoordinate(latitude:0,longitude:0),.init(latitude:0,longitude:15)]
        let payload = Data("[\(helper.row(lat:0,lon:0)),\(helper.row(lat:0,lon:15,cloud:"null"))]".utf8)
        let samples = try WeatherParser.parse(payload,requested:requested,fetchedAt:helper.now)
        let result = WeatherFetchResult(samples:samples,failedBatches:0)
        XCTAssertFalse(result.isComplete(for:requested,at:helper.now))
    }
    func testPrecipitationMovesTowardSurfaceInBothHemispheres() {
        for coordinate in [GeoCoordinate(latitude:60,longitude:100),.init(latitude:-60,longitude:-100)] {
            let start = WeatherGeometry.precipitationPosition(at:coordinate,progress:0,offset:0)
            let end = WeatherGeometry.precipitationPosition(at:coordinate,progress:1,offset:0)
            XCTAssertEqual(sqrt(start.x*start.x+start.y*start.y+start.z*start.z),1.12,accuracy:0.0001)
            XCTAssertEqual(sqrt(end.x*end.x+end.y*end.y+end.z*end.z),1.045,accuracy:0.0001)
            XCTAssertLessThan(abs(end.y),abs(start.y))
        }
    }
}
