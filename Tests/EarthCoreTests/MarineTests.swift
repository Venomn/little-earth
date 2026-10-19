import XCTest
@testable import EarthCore

final class MarineTests: XCTestCase {
    func testOceanStoriesRespectBasinsLatitudeAndDateline() throws {
        let catalog = try MarineCatalog.bundled()
        for longitude in [-179.0,179,-140] {
            XCTAssertEqual(catalog.story(at:.init(latitude:5,longitude:longitude))?.entry.id,"warm-ocean-yellowfin")
        }
        XCTAssertEqual(catalog.story(at:.init(latitude:35,longitude:-150))?.entry.id,"pacific-albacore")
        XCTAssertEqual(catalog.story(at:.init(latitude:40,longitude:-40))?.entry.id,"atlantic-bluefin")
        XCTAssertEqual(catalog.story(at:.init(latitude:35,longitude:18))?.entry.id,"mediterranean-bluefin")
        XCTAssertEqual(catalog.story(at:.init(latitude:0,longitude:75))?.entry.id,"warm-ocean-yellowfin")
        for longitude in [-90.0,0,90] {
            XCTAssertEqual(catalog.story(at:.init(latitude:89,longitude:longitude))?.entry.id,"arctic-cod")
        }
        XCTAssertEqual(catalog.story(at:.init(latitude:85,longitude:0))?.entry.id,"arctic-cod")
        // Greenland Sea is outside the named basins in this generalized atlas.
        XCTAssertNil(catalog.story(at:.init(latitude:80,longitude:0)))
        XCTAssertEqual(catalog.region(at:.init(latitude:35,longitude:-150))?.name(in:.english),"North Pacific Ocean")
        XCTAssertEqual(catalog.story(at:.init(latitude:-65,longitude:0))?.entry.id,"southern-icefish")
    }
    func testLandInlandWaterAndInvalidPointsCannotBecomeOceanStories() throws {
        let catalog = try MarineCatalog.bundled()
        for point in [GeoCoordinate(latitude:39.9,longitude:116.4),.init(latitude:-25,longitude:134),.init(latitude:40,longitude:51),.init(latitude:44,longitude:-87),.init(latitude:-80,longitude:0),.init(latitude:.nan,longitude:0)] {
            XCTAssertNil(catalog.story(at:point),"\(point)")
        }
    }
    func testBilingualContentIsShortSourcedAndValidated() throws {
        let catalog = try MarineCatalog.bundled()
        XCTAssertGreaterThanOrEqual(catalog.entries.count,6)
        for entry in catalog.entries {
            for language in AppLanguage.allCases {
                XCTAssertTrue(entry.text(in:language).isValid)
            }
            XCTAssertEqual(URL(string:entry.sourceURL)?.scheme,"https")
        }
        let encoded = try JSONEncoder().encode(catalog.entries)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [[String:Any]])
        data[0]["latitudeRange"] = [30,-30]
        XCTAssertThrowsError(try MarineCatalog(data:JSONSerialization.data(withJSONObject:data)))
    }
}
