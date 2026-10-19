import XCTest
@testable import EarthCore

final class CultureTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from:value)! }
    func testBundledRegionsDoNotAssignNearbyCultureToTheOcean() throws {
        let atlas = try PlaceAtlas.bundled()
        XCTAssertEqual(atlas.place(at:.init(latitude:35.68,longitude:139.76))?.id,"JPN")
        XCTAssertEqual(atlas.place(at:.init(latitude:-25,longitude:134))?.id,"AUS")
        XCTAssertEqual(atlas.place(at:.init(latitude:39.9,longitude:116.4))?.id,"CHN")
        XCTAssertEqual(atlas.place(at:.init(latitude:38.9,longitude:-77.0))?.id,"USA")
        XCTAssertNil(atlas.place(at:.init(latitude:0,longitude:-140)))
        XCTAssertNil(atlas.place(at:.init(latitude:0,longitude:179)))
        XCTAssertNil(atlas.place(at:.init(latitude:.nan,longitude:0)))
    }
    func testDatelinePolygonAndHole() throws {
        let data = Data(#"{"features":[{"properties":{"ADM0_A3":"TST","NAME_ZH":"测试"},"geometry":{"type":"Polygon","coordinates":[[[170,-10],[-170,-10],[-170,10],[170,10],[170,-10]],[[175,-2],[-175,-2],[-175,2],[175,2],[175,-2]]]}}]}"#.utf8)
        let atlas = try PlaceAtlas(data:data)
        XCTAssertNotNil(atlas.place(at:.init(latitude:5,longitude:179)))
        XCTAssertNotNil(atlas.place(at:.init(latitude:5,longitude:-179)))
        XCTAssertNil(atlas.place(at:.init(latitude:0,longitude:179)))
        XCTAssertNil(atlas.place(at:.init(latitude:5,longitude:0)))
    }
    func testNorthernAndSouthernSeasonalStoriesUseLocalDate() throws {
        let catalog = try CultureCatalog.bundled(), now = date("2026-10-16T00:00:00Z")
        XCTAssertEqual(catalog.story(placeID:"JPN",at:.init(latitude:35,longitude:135),date:now)?.id,"japan-autumn")
        XCTAssertEqual(catalog.story(placeID:"AUS",at:.init(latitude:-33,longitude:116),date:now)?.id,"australia-spring")
        XCTAssertEqual(catalog.story(placeID:"AUS",at:.init(latitude:-12,longitude:131),date:now)?.id,"australia-tropical-dry")
        let before = date("2026-08-31T14:59:00Z"), after = date("2026-08-31T15:01:00Z")
        XCTAssertEqual(catalog.story(placeID:"JPN",at:.init(latitude:35,longitude:135),date:before)?.id,"japan-summer")
        XCTAssertEqual(catalog.story(placeID:"JPN",at:.init(latitude:35,longitude:135),date:after)?.id,"japan-autumn")
    }
    func testFestivalWindowAndCrossYearDoNotPretendAnEventIsToday() throws {
        let catalog = try CultureCatalog.bundled(), point = GeoCoordinate(latitude:19.4,longitude:-99.1)
        XCTAssertEqual(catalog.story(placeID:"MEX",at:point,date:date("2026-10-29T18:00:00Z"))?.id,"mexico-remembrance")
        XCTAssertNotEqual(catalog.story(placeID:"MEX",at:point,date:date("2026-10-16T18:00:00Z"))?.id,"mexico-remembrance")
        let japan = GeoCoordinate(latitude:35,longitude:135)
        XCTAssertEqual(catalog.story(placeID:"JPN",at:japan,date:date("2026-12-30T12:00:00Z"))?.id,"japan-new-year")
        XCTAssertEqual(catalog.story(placeID:"JPN",at:japan,date:date("2027-01-02T12:00:00Z"))?.id,"japan-new-year")
        XCTAssertNil(catalog.story(placeID:"UNKNOWN",at:point,date:Date()))
    }
    func testBundledStoriesAreShortSourcedAndExplicitlyScoped() throws {
        let catalog = try CultureCatalog.bundled()
        XCTAssertGreaterThanOrEqual(Set(catalog.entries.flatMap(\.placeIDs)).count,10)
        XCTAssertEqual(Set(catalog.entries.map(\.id)).count,catalog.entries.count)
        for entry in catalog.entries {
            XCTAssertFalse(entry.regionLabel.isEmpty)
            XCTAssertLessThanOrEqual(entry.body.count,110)
            XCTAssertEqual(URL(string:entry.sourceURL)?.scheme,"https")
            XCTAssertNotNil(TimeZone(identifier:entry.timeZone))
            XCTAssertFalse(entry.body.contains("所有当地人"))
        }
    }
    func testInvalidCatalogCannotReachRenderingOrDateSelection() throws {
        let entry = try CultureCatalog.bundled().entries[0]
        let encoded = try JSONEncoder().encode([entry])
        let original = try JSONSerialization.jsonObject(with:encoded) as! [[String:Any]]
        for (key,value): (String,Any) in [("timeZone","Missing/Zone"),("sourceURL","file:///tmp/example"),("months",[0]),("window",[230,301]),("bounds",[0,10,20,-10]),("bounds",[0,1,2])] {
            var altered = original; altered[0][key] = value
            XCTAssertThrowsError(try CultureCatalog(data:JSONSerialization.data(withJSONObject:altered)),key)
        }
        XCTAssertThrowsError(try CultureCatalog(data:JSONSerialization.data(withJSONObject:original+original)))
    }
    func testRegionalGatesAndFestivalEndFallBackWithoutLeakingStories() throws {
        let catalog = try CultureCatalog.bundled()
        let october = date("2026-10-16T12:00:00Z")
        XCTAssertNil(catalog.story(placeID:"JPN",at:.init(latitude:91,longitude:135),date:october))
        XCTAssertEqual(catalog.story(placeID:"AUS",at:.init(latitude:-12,longitude:131),date:date("2026-11-01T12:00:00Z"))?.id,"australia-tropical-wet")
        XCTAssertNotEqual(catalog.story(placeID:"AUS",at:.init(latitude:-33,longitude:116),date:date("2026-04-01T12:00:00Z"))?.id,"australia-spring")
        XCTAssertNotEqual(catalog.story(placeID:"MEX",at:.init(latitude:19,longitude:-99),date:date("2026-11-04T18:00:00Z"))?.id,"mexico-remembrance")
        XCTAssertEqual(catalog.story(placeID:"JPN",at:.init(latitude:35,longitude:135),date:date("2027-01-08T12:00:00Z"))?.id,"japan-winter")
    }
}
