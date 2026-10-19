import AppKit
import XCTest
import EarthCore
@testable import LittleEarth

@MainActor final class PopoverLayoutTests: XCTestCase {
    func testPopoverContentFillsHostAfterReopeningAndResizing() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let parent = CompanionPanel(contentRect:NSRect(x:screen.maxX-330,y:screen.midY,width:330,height:392),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false; parent.orderFrontRegardless()
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires WindowServer") }
        let popover = WeatherDetailPopover(), content: WeatherDetailController
        content = popover.cardController
        let dismissal = PopoverDismissal(popover:popover,onOutsideClick:{ _ in })
        defer { withExtendedLifetime(dismissal) {} }
        defer { popover.close() }
        func card(long: Bool) -> PlaceCard {
            PlaceCard(region:"Algeria",theme:"Around the globe",title:long ? "Golden fins in the blue":"More stories to come",body:long ? String(repeating:"These long-distance swimmers hunt fish and squid. ",count:5):"We have not added a cultural story for this region yet. You can still explore its day and night, and regional weather.",weather:"Daytime · 22°C · Partly cloudy · Regional",weatherDetails:String(repeating:"Regional weather and sample provenance\n",count:6),sourceName:nil,sourceURL:nil)
        }
        func settle() { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.35)); content.view.layoutSubtreeIfNeeded() }
        var verticalChrome: CGFloat?
        var bottomInset: CGFloat?
        func check(_ phase: String, file: StaticString = #filePath, line: UInt = #line) throws {
            settle()
            XCTAssertTrue(popover.isShown,phase,file:file,line:line)
            let view = content.view, host = try XCTUnwrap(view.superview)
            print("LAYOUT \(phase): preferred=\(content.preferredContentSize), popover=\(popover.contentSize), view=\(view.frame), host=\(host.bounds), window=\(String(describing:view.window?.frame))")
            XCTAssertEqual(view.frame.height,content.preferredContentSize.height,accuracy:1,phase,file:file,line:line)
            if verticalChrome == nil { verticalChrome = host.bounds.height-view.frame.height; bottomInset = view.frame.minY }
            XCTAssertEqual(popover.contentSize.height,content.preferredContentSize.height,accuracy:1,phase,file:file,line:line)
            XCTAssertEqual(host.bounds.height-view.frame.height,verticalChrome!,accuracy:1,phase,file:file,line:line)
            XCTAssertEqual(view.frame.minY,bottomInset!,accuracy:1,phase,file:file,line:line)
            let top = try XCTUnwrap(view.subviews.first)
            XCTAssertEqual(view.bounds.maxY-top.frame.maxY,18,accuracy:1,phase,file:file,line:line)
        }
        for origin in [NSPoint(x:screen.maxX-330,y:screen.minY), NSPoint(x:screen.maxX-330,y:screen.maxY-392)] {
          parent.setFrameOrigin(origin)
          verticalChrome = nil; bottomInset = nil
          for long in [true,false] {
            content.update(card(long:long),reset:true)
            popover.show(relativeTo:NSRect(x:165,y:165,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
            try check("open \(long)")
            let toggle = try XCTUnwrap(content.view.subviews.compactMap { $0 as? NSButton }.first)
            toggle.performClick(nil)
            try check("expand \(long)")
            content.update(card(long:!long))
            try check("update \(!long)")
            content.view.subviews.compactMap { $0 as? NSButton }.first!.performClick(nil)
            try check("collapse")
            popover.close(); settle()
          }
        }
    }
}
