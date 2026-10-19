import XCTest
@testable import EarthCore

final class LocalizationTests: XCTestCase {
    func testEnglishIsDefaultAndOnlyExplicitSupportedChoicePersists() {
        let suite = "LittleEarth.LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(["zh-Hans"],forKey:"AppleLanguages")
        XCTAssertEqual(AppLanguage.saved(in:defaults),.english)
        AppLanguage.simplifiedChinese.save(in:defaults)
        XCTAssertEqual(AppLanguage.saved(in:UserDefaults(suiteName:suite)!),.simplifiedChinese)
        defaults.set("fr",forKey:AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.saved(in:defaults),.english)
    }
    func testEveryUserInterfaceMessageHasMatchingTranslationsAndFormatArguments() throws {
        try L10n.validateResources()
        for language in AppLanguage.allCases {
            let strings = L10n(language)
            for key in UIString.allCases { XCTAssertFalse(strings.text(key).isEmpty) }
        }
        XCTAssertEqual(L10n(.english).text(.showEarth),"Show Little Earth")
        XCTAssertEqual(L10n(.simplifiedChinese).text(.showEarth),"显示小地球")
        XCTAssertEqual(L10n(.english).weatherDescription(code:61),"Rain")
        XCTAssertEqual(L10n(.simplifiedChinese).weatherDescription(code:61),"雨")
        XCTAssertEqual(L10n(.english).weatherDescription(code:12),"Weather code 12")
    }
    func testDatesAndCultureUseSelectedLanguageWithoutChangingSelection() throws {
        let date = ISO8601DateFormatter().date(from:"2026-10-16T10:30:00Z")!
        XCTAssertTrue(L10n(.english).date(date,timeZone:TimeZone(secondsFromGMT:0)!).contains("Oct"))
        XCTAssertTrue(L10n(.simplifiedChinese).date(date,timeZone:TimeZone(secondsFromGMT:0)!).contains("年"))
        for entry in try CultureCatalog.bundled().entries {
            let en = entry.text(in:.english), zh = entry.text(in:.simplifiedChinese)
            XCTAssertFalse(en.body.isEmpty); XCTAssertFalse(zh.body.isEmpty)
            XCTAssertNil(en.body.range(of:"\\p{Han}",options:.regularExpression))
            XCTAssertNotEqual(en.title,zh.title)
            XCTAssertLessThanOrEqual(en.body.count,420)
        }
        let atlas = try PlaceAtlas.bundled()
        let japan = try XCTUnwrap(atlas.place(at:.init(latitude:35.68,longitude:139.76)))
        XCTAssertEqual(japan.name(in:.english),"Japan")
        XCTAssertEqual(japan.name(in:.simplifiedChinese),"日本")
    }
}
