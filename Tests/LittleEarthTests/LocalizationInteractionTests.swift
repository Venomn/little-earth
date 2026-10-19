import AppKit
import XCTest
import EarthCore
@testable import LittleEarth

@MainActor final class LocalizationInteractionTests: XCTestCase {
    func testLanguageSwitchPreservesExpansionAndWeatherRefreshKeepsReadingControls() throws {
        _ = NSApplication.shared
        let story = try XCTUnwrap(CultureCatalog.bundled().entries.first)
        let parent = CompanionPanel(contentRect:NSRect(x:60,y:60,width:240,height:240),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false; parent.orderFrontRegardless()
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires WindowServer") }
        let popover = WeatherDetailPopover(), controller = popover.cardController
        defer { popover.close() }
        func checkSize() {
            RunLoop.main.run(until:Date(timeIntervalSinceNow:0.15))
            XCTAssertEqual(popover.contentSize,controller.preferredContentSize)
            XCTAssertEqual(controller.view.frame.size,popover.contentSize)
        }
        func card(_ language: AppLanguage, night: Bool = false) -> PlaceCard {
            let text = story.text(in:language), strings = L10n(language)
            return PlaceCard(language:language,region:text.regionLabel,theme:text.theme,title:text.title,body:text.body,
                weather:strings.text(night ? .night:.day),weatherDetails:strings.text(.weatherMissingDetails),
                sourceName:text.sourceName,sourceURL:URL(string:story.sourceURL))
        }
        func labels() -> [String] { controller.view.subviews.compactMap { ($0 as? NSTextField)?.stringValue } }
        func buttons() -> [NSButton] { controller.view.subviews.compactMap { $0 as? NSButton } }
        controller.update(card(.simplifiedChinese))
        popover.show(relativeTo:NSRect(x:120,y:120,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
        checkSize()
        XCTAssertEqual(buttons().first?.title,L10n(.simplifiedChinese).text(.expandWeather))
        buttons().first?.performClick(nil)
        controller.update(card(.english))
        checkSize()
        XCTAssertEqual(buttons().first?.title,L10n(.english).text(.collapseWeather))
        XCTAssertTrue(labels().contains(story.text(in:.english).body))
        XCTAssertTrue(labels().contains(L10n(.english).text(.weatherMissingDetails)))
        XCTAssertFalse(labels().contains(story.text(in:.simplifiedChinese).body))
        let controls = controller.view.subviews
        controller.update(card(.english,night:true))
        checkSize()
        XCTAssertTrue(zip(controls,controller.view.subviews).allSatisfy { $0 === $1 })
        XCTAssertTrue(labels().contains("Nighttime"))
        XCTAssertEqual(buttons().first?.title,L10n(.english).text(.collapseWeather))
        controller.update(card(.simplifiedChinese))
        checkSize()
        XCTAssertEqual(buttons().first?.title,L10n(.simplifiedChinese).text(.collapseWeather))
        XCTAssertTrue(labels().contains(story.text(in:.simplifiedChinese).body))
    }
}
