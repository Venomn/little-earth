import XCTest
@testable import EarthCore

final class CityLightsTests: XCTestCase {
    func testBundledCitiesRetainRealCoordinatesAcrossHemispheres() throws {
        let cities = try CityLightCatalog.bundled().cities
        let tokyo = try XCTUnwrap(cities.first { $0.name == "Tokyo" })
        XCTAssertEqual(tokyo.coordinate.latitude,35.7,accuracy:0.2)
        XCTAssertEqual(tokyo.coordinate.longitude,139.7,accuracy:0.2)
        let sydney = try XCTUnwrap(cities.first { $0.name == "Sydney" })
        XCTAssertEqual(sydney.coordinate.latitude,-33.9,accuracy:0.2)
        XCTAssertEqual(sydney.coordinate.longitude,151.2,accuracy:0.2)
        XCTAssertTrue(cities.contains { $0.coordinate.longitude < -70 })
        XCTAssertTrue(cities.allSatisfy { $0.coordinate.isValid })
        XCTAssertGreaterThan(cities.count,200)
    }
    func testMalformedCoordinatesNeverProduceLightsAtDefaultOrigin() throws {
        for payload in [
            #"[{"name":"Broken","latitude":91,"longitude":10,"population":100}]"#,
            #"[{"name":"Broken","latitude":10,"longitude":181,"population":100}]"#,
            #"[{"name":"Broken","latitude":10,"population":100}]"#,
            #"[{"name":"Broken","latitude":10,"longitude":0,"population":-1}]"#
        ] { XCTAssertThrowsError(try CityLightCatalog(data:Data(payload.utf8))) }
    }
}
