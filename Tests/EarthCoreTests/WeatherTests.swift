import XCTest
@testable import EarthCore

final class WeatherTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from:text)! }
    func testCoordinatesRoundTripAndDatelineDistance() {
        for p in [GeoCoordinate(latitude:31,longitude:121),GeoCoordinate(latitude:-70,longitude:-179)] {
            let q = GeoCoordinate(vector:p.vector)
            XCTAssertEqual(q.latitude,p.latitude,accuracy:0.0001)
            XCTAssertEqual(q.longitude,p.longitude,accuracy:0.0001)
        }
        XCTAssertEqual(GeoCoordinate(latitude:0,longitude:179).distance(to:.init(latitude:0,longitude:-179)),2,accuracy:0.001)
    }
    func testSunEquinoxAndSolsticeAreGeographicNotCameraBased() {
        let spring = SolarPosition.coordinate(at:date("2026-03-20T12:00:00Z"))
        XCTAssertEqual(spring.latitude,0,accuracy:0.5)
        XCTAssertEqual(spring.longitude,2,accuracy:1)
        XCTAssertEqual(SolarPosition.coordinate(at:date("2026-06-21T12:00:00Z")).latitude,23.44,accuracy:0.2)
        XCTAssertLessThan(SolarPosition.coordinate(at:date("2026-12-21T12:00:00Z")).latitude,-23)
        XCTAssertGreaterThan(abs(SolarPosition.coordinate(at:date("2026-03-20T00:00:00Z")).longitude),175)
    }
    func row(lat: Double,lon: Double,cloud: String="80", interval: Int=900) -> String {
        """
        {"latitude":\(lat),"longitude":\(lon),"current_units":{"temperature_2m":"°C","cloud_cover":"%","rain":"mm","showers":"mm","snowfall":"cm"},"current":{"time":1800000000,"interval":\(interval),"temperature_2m":-2,"cloud_cover":\(cloud),"rain":0.5,"showers":0.25,"snowfall":0.1,"weather_code":73}}
        """
    }
    func testReorderedPayloadUsesCoordinatesAndNormalizesPrecipitationInterval() throws {
        let requested = [GeoCoordinate(latitude:0,longitude:0),GeoCoordinate(latitude:45,longitude:120)]
        let data = Data("[\(row(lat:45,lon:120)),\(row(lat:0,lon:0))]".utf8)
        let samples = try WeatherParser.parse(data,requested:requested,fetchedAt:now)
        XCTAssertEqual(samples.count,2)
        XCTAssertEqual(samples[0].coordinate.latitude,45)
        XCTAssertEqual(samples[0].rainMMPerHour,3,accuracy:0.001)
        XCTAssertEqual(samples[0].snowCMPerHour,0.4,accuracy:0.001)
        XCTAssertTrue(samples[0].usable(at:now))
    }
    func testMissingCloudIsUnknownNotClearAndUnrelatedCoordinateIsRejected() throws {
        let requested = [GeoCoordinate(latitude:0,longitude:0)]
        XCTAssertTrue(try WeatherParser.parse(Data(row(lat:0,lon:0,cloud:"null").utf8),requested:requested,fetchedAt:now).isEmpty)
        XCTAssertThrowsError(try WeatherParser.parse(Data(row(lat:45,lon:120).utf8),requested:requested,fetchedAt:now))
        XCTAssertThrowsError(try WeatherParser.parse(Data("[\(row(lat:0,lon:0)),\(row(lat:0,lon:0))]".utf8),requested:requested,fetchedAt:now))
    }
    func testExpiredOrFutureSamplesNeverBecomeLiveAfterCacheReload() throws {
        let sample = try XCTUnwrap(WeatherParser.parse(Data(row(lat:0,lon:0).utf8),requested:[.init(latitude:0,longitude:0)],fetchedAt:now).first)
        XCTAssertFalse(sample.usable(at:now.addingTimeInterval(10801)))
        XCTAssertFalse(sample.usable(at:now.addingTimeInterval(-901)))
        let cache = WeatherSnapshot(samples:[sample])
        let restored = try WeatherSnapshot.decode(JSONEncoder().encode(cache))
        XCTAssertFalse(restored.samples[0].usable(at:now.addingTimeInterval(10801)))
        var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(cache)) as! [String:Any]
        object["version"] = 999
        XCTAssertThrowsError(try WeatherSnapshot.decode(JSONSerialization.data(withJSONObject:object)))
    }
    func testGlobalGridCoversBothHemispheresAndHonorsRequestCoordinates() throws {
        let grid = WeatherGrid.coordinates
        XCTAssertGreaterThan(grid.count,150)
        XCTAssertLessThan(grid.count,210)
        XCTAssertTrue(grid.contains { $0.latitude > 80 })
        XCTAssertTrue(grid.contains { $0.latitude < -80 })
        let url = WeatherClient.url(for:Array(grid.prefix(24)))
        let query = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "cell_selection" }?.value,"nearest")
        XCTAssertEqual(query.first { $0.name == "timeformat" }?.value,"unixtime")
        XCTAssertEqual(query.first { $0.name == "latitude" }?.value?.split(separator:",").count,24)
    }
}
