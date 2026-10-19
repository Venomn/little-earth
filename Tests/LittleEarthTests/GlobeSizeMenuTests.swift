import AppKit
import XCTest
import EarthCore
@testable import LittleEarth

@MainActor final class GlobeSizeMenuTests: XCTestCase {
    func testInlineSliderFitsActualMenuHostAtScreenEdges() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("Requires WindowServer") }
        let visible = screen.visibleFrame
        for language in AppLanguage.allCases {
            for position in [NSPoint(x:visible.minX+10,y:visible.maxY-20),NSPoint(x:visible.maxX-10,y:visible.minY+20)] {
                let menu = NSMenu(); menu.autoenablesItems = false
                menu.minimumWidth = language == .english ? 260:370
                let item = GlobeSizeMenuView.menuItem(width:320,maximumWidth:660,language:language) { $0 }
                menu.addItem(item)
                XCTAssertNil(item.submenu,"The control must not depend on a second menu window")
                let view = try XCTUnwrap(item.view as? GlobeSizeMenuView)
                var inspected = false
                let timer = Timer(timeInterval:0.15,repeats:false) { _ in
                    MainActor.assumeIsolated {
                        view.layoutSubtreeIfNeeded()
                        XCTAssertNotNil(view.window)
                        XCTAssertGreaterThanOrEqual(view.bounds.width,260)
                        XCTAssertEqual(view.visibleRect.width,view.bounds.width,accuracy:1)
                        for child in view.subviews {
                            XCTAssertTrue(view.bounds.contains(child.frame),"All labels and the full slider must fit the hosted view")
                        }
                        if let window = view.window {
                            let frame = window.convertToScreen(view.convert(view.bounds,to:nil))
                            XCTAssertTrue(visible.insetBy(dx:-2,dy:-2).contains(frame))
                        }
                        if let directory = ProcessInfo.processInfo.environment["LITTLE_EARTH_QA_OUTPUT"],
                           let host = view.window?.contentView,
                           let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
                            host.cacheDisplay(in:host.bounds,to:bitmap)
                            let edge = position.x < visible.midX ? "left":"right"
                            let path = URL(fileURLWithPath:directory).appendingPathComponent("native-menu-\(language.rawValue)-\(edge).png")
                            do { try bitmap.representation(using:.png,properties:[:])?.write(to:path) }
                            catch { XCTFail("Could not save hosted menu snapshot") }
                        }
                        inspected = true; menu.cancelTracking()
                    }
                }
                RunLoop.main.add(timer,forMode:.eventTracking)
                menu.popUp(positioning:item,at:position,in:nil)
                timer.invalidate()
                XCTAssertTrue(inspected,"Must inspect while the real menu is open")
            }
        }
    }

    func testContinuousSliderUpdatesARealWindowAndReflectsConstrainedSizeInBothLanguages() throws {
        _ = NSApplication.shared
        let panel = CompanionPanel(contentRect:NSRect(x:300,y:300,width:240,height:240),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        for language in AppLanguage.allCases {
            var updates = 0
            let control = GlobeSizeMenuView(width:317.25,maximumWidth:660,language:language) { width in
                updates += 1
                let old = panel.frame
                let requested = CGRect(x:old.midX-width/2,y:old.midY-width/2,width:width,height:width)
                panel.setFrame(GlobeSizing.fitting(requested,to:CGRect(x:0,y:0,width:500,height:500)),display:true)
                return panel.frame.width
            }
            XCTAssertTrue(control.slider.isContinuous)
            XCTAssertEqual(control.slider.doubleValue,317.25)
            XCTAssertEqual(control.slider.accessibilityLabel(),L10n(language).text(.size))
            for width in [225.5,388.75,660] {
                control.slider.doubleValue = width
                XCTAssertTrue(control.slider.sendAction(control.slider.action,to:control.slider.target))
                // AppKit aligns native window frames to integral display units.
                XCTAssertEqual(panel.frame.width,min(width,500),accuracy:1)
                XCTAssertEqual(panel.frame.height,panel.frame.width)
                XCTAssertEqual(control.slider.doubleValue,Double(panel.frame.width),accuracy:0.01)
                XCTAssertEqual(GlobeSizing.restoredWidth(savedGlobeSize:Double(panel.frame.width/1.5)),panel.frame.width,accuracy:0.01)
            }
            XCTAssertEqual(updates,3)
        }
    }
}
