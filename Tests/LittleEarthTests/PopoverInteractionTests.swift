import AppKit
import XCTest
import EarthCore
@testable import LittleEarth

@MainActor final class PopoverInteractionTests: XCTestCase {
    func testOutsideClickClosesAndStillReachesDestinationWindow() throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect:NSRect(x:40,y:40,width:240,height:240),styleMask:.borderless,backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false; parent.orderFront(nil)
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires a logged-in macOS WindowServer session") }
        let popover = NSPopover(); popover.animates = false
        let content = NSViewController(); content.view = NSView(frame:NSRect(x:0,y:0,width:120,height:80))
        popover.contentViewController = content
        var rotation = Rotation()
        var dismissedEvent: NSEvent?
        let dismissal = PopoverDismissal(popover:popover,onOutsideClick:{ dismissedEvent = $0 },onClose:{ rotation.setPaused(false) },onShow:{ rotation.setPaused(true) })
        defer { withExtendedLifetime(dismissal) {} }
        popover.show(relativeTo:NSRect(x:80,y:80,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(rotation.isPaused)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:20,y:20),modifierFlags:[],timestamp:100,windowNumber:parent.windowNumber,context:nil,eventNumber:10,clickCount:1,pressure:1))
        let forwarded = dismissal.handleLocalEvent(event)
        XCTAssertTrue(forwarded === event, "Dismissal must not swallow the destination's click")
        XCTAssertTrue(dismissedEvent === event)
        XCTAssertFalse(popover.isShown)
        XCTAssertFalse(rotation.isPaused)
        // Reopen must install one fresh set of monitors and remain dismissible.
        popover.show(relativeTo:NSRect(x:80,y:80,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(rotation.isPaused)
        NSApp.sendEvent(event)
        XCTAssertFalse(popover.isShown, "Real AppKit dispatch must run the installed local monitor")
        XCTAssertFalse(rotation.isPaused)
    }
    func testInsideCardKeepsItOpenAndEscapeCloses() throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect:NSRect(x:40,y:40,width:240,height:240),styleMask:.borderless,backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false; parent.orderFront(nil)
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires a logged-in macOS WindowServer session") }
        let popover = NSPopover(); popover.animates = false
        let content = NSViewController(); content.view = NSView(frame:NSRect(x:0,y:0,width:120,height:80))
        popover.contentViewController = content
        let dismissal = PopoverDismissal(popover:popover,onOutsideClick:{ _ in XCTFail("Inside click must not dismiss") })
        defer { withExtendedLifetime(dismissal) {} }
        popover.show(relativeTo:NSRect(x:80,y:80,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
        let window = try XCTUnwrap(content.view.window)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:20,y:20),modifierFlags:[],timestamp:100,windowNumber:window.windowNumber,context:nil,eventNumber:11,clickCount:1,pressure:1))
        XCTAssertTrue(dismissal.handleLocalEvent(click) === click)
        XCTAssertTrue(popover.isShown)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:101,windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
        XCTAssertNil(dismissal.handleLocalEvent(escape))
        XCTAssertFalse(popover.isShown)
    }
    func testCompanionCardOwnsKeyboardFocusAndEscapeDispatchClosesIt() throws {
        _ = NSApplication.shared
        let parent = CompanionPanel(contentRect:NSRect(x:40,y:40,width:240,height:240),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false; parent.hidesOnDeactivate = false
        parent.orderFrontRegardless()
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires a logged-in macOS WindowServer session") }
        let popover = WeatherDetailPopover()
        let content = popover.cardController
        content.update(PlaceCard(region:"Earth",theme:"Culture",title:"A local story",body:"Reading text",weather:"Daytime",weatherDetails:"Weather details",sourceName:nil,sourceURL:nil))
        popover.contentViewController = content
        var closed = 0
        var rotation = Rotation()
        let dismissal = PopoverDismissal(popover:popover,onOutsideClick:{ _ in },onClose:{ closed += 1; rotation.setPaused(false) },onShow:{ rotation.setPaused(true) })
        defer { withExtendedLifetime(dismissal) {} }
        for attempt in 1...2 {
            popover.show(relativeTo:NSRect(x:80,y:80,width:1,height:1),of:parent.contentView!,preferredEdge:.maxY)
            XCTAssertTrue(popover.isShown)
            let focused = NSApp.keyWindow
            XCTAssertTrue(focused === parent || focused === content.view.window,
                          "A nonactivating companion must acquire keyboard focus while the card is open")
            guard let focused else { return }
            XCTAssertTrue(rotation.isPaused)
            if attempt == 2 {
                let button = try XCTUnwrap(content.view.subviews.compactMap { $0 as? NSButton }.first)
                button.performClick(nil)
                focused.makeFirstResponder(button)
                XCTAssertTrue(popover.isShown, "Expanding weather must retain the card")
            }
            let escape = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:101,windowNumber:focused.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
            NSApp.sendEvent(escape)
            XCTAssertFalse(popover.isShown)
            XCTAssertEqual(closed,attempt)
            XCTAssertFalse(rotation.isPaused)
            XCTAssertFalse(content.view.window?.isKeyWindow ?? false)
            XCTAssertTrue(dismissal.handleLocalEvent(escape) === escape, "A closed card must not consume keys")
        }
    }
    func testDismissingGlobeClickDoesNotReopenButFollowingClickAndAccessibilityStillWork() throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect:NSRect(x:40,y:40,width:240,height:240),styleMask:.borderless,backing:.buffered,defer:false)
        parent.isReleasedWhenClosed = false
        let globe = GlobeView(frame:NSRect(x:0,y:0,width:240,height:240))
        parent.contentView = globe; parent.orderFront(nil)
        defer { parent.close() }
        guard parent.windowNumber > 0 else { throw XCTSkip("Requires a logged-in macOS WindowServer session") }
        globe.layoutSubtreeIfNeeded()
        _ = globe.snapshot() // Render once so SceneKit has a presentation tree for picking.
        var selections = 0
        globe.onSelect = { _,_ in selections += 1 }
        func event(_ type: NSEvent.EventType, _ number: Int, x: CGFloat = 120) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:120),modifierFlags:[],timestamp:Double(number),windowNumber:parent.windowNumber,context:nil,eventNumber:number,clickCount:1,pressure:1)!
        }
        globe.mouseDown(with:event(.leftMouseDown,20)); globe.mouseUp(with:event(.leftMouseUp,21))
        XCTAssertEqual(selections,1)
        let dismiss = event(.leftMouseDown,22)
        globe.suppressSelection(for:dismiss)
        globe.mouseDown(with:dismiss); globe.mouseUp(with:event(.leftMouseUp,23))
        XCTAssertEqual(selections,1, "The click that closes must not also reopen on mouseUp")
        globe.mouseDown(with:event(.leftMouseDown,24)); globe.mouseUp(with:event(.leftMouseUp,25))
        XCTAssertEqual(selections,2, "Suppression belongs only to the dismissing gesture")
        globe.mouseDown(with:event(.leftMouseDown,26)); globe.mouseDragged(with:event(.leftMouseDragged,27,x:150)); globe.mouseUp(with:event(.leftMouseUp,28,x:150))
        XCTAssertEqual(selections,2, "A drag must not open a card")
        XCTAssertTrue(globe.accessibilityPerformPress())
        XCTAssertEqual(selections,3)
    }
}
