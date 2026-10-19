import AppKit
import XCTest
@testable import LittleEarth

@MainActor final class GlobeDragTests: XCTestCase {
    func testPlainDragMovesWindowWithoutSpinningOrSelectingAndOptionDragSpins() throws {
        _ = NSApplication.shared
        let panel = CompanionPanel(contentRect:NSRect(x:100,y:100,width:240,height:240),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false
        let globe = GlobeView(frame:NSRect(x:0,y:0,width:240,height:240))
        panel.contentView = globe; panel.orderFrontRegardless()
        defer { panel.close() }
        guard panel.windowNumber > 0 else { throw XCTSkip("Requires WindowServer") }
        globe.layoutSubtreeIfNeeded(); _ = globe.snapshot()
        var selections = 0
        globe.onSelect = { _,_ in selections += 1 }
        func event(_ type: NSEvent.EventType, _ number: Int, point: NSPoint, option: Bool = false) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:option ? .option:[],timestamp:Double(number)/30,windowNumber:panel.windowNumber,context:nil,eventNumber:number,clickCount:1,pressure:1)!
        }
        let origin = panel.frame.origin, yaw = globe.rotation.yaw
        globe.mouseDown(with:event(.leftMouseDown,1,point:NSPoint(x:120,y:120)))
        globe.mouseDragged(with:event(.leftMouseDragged,2,point:NSPoint(x:122,y:120)))
        XCTAssertEqual(panel.frame.origin,origin,"Small click jitter must not move the window")
        globe.mouseDragged(with:event(.leftMouseDragged,3,point:NSPoint(x:150,y:140),option:true))
        XCTAssertEqual(panel.frame.origin.x,origin.x+30,accuracy:0.1)
        XCTAssertEqual(panel.frame.origin.y,origin.y+20,accuracy:0.1)
        // The cursor stays at the same screen position after the window moved.
        globe.mouseUp(with:event(.leftMouseUp,4,point:NSPoint(x:120,y:120)))
        XCTAssertEqual(globe.rotation.yaw,yaw)
        XCTAssertEqual(selections,0)
        XCTAssertFalse(globe.rotation.isDragging)
        let beforeEdgeDrag = panel.frame
        globe.mouseDown(with:event(.leftMouseDown,12,point:NSPoint(x:200,y:120)))
        globe.mouseDragged(with:event(.leftMouseDragged,13,point:NSPoint(x:230,y:120)))
        globe.mouseUp(with:event(.leftMouseUp,14,point:NSPoint(x:200,y:120)))
        XCTAssertEqual(panel.frame.size,beforeEdgeDrag.size,"The rim must move the globe, never resize it")
        XCTAssertEqual(panel.frame.minX,beforeEdgeDrag.minX+30,accuracy:0.1)
        XCTAssertEqual(selections,0)
        let movedOrigin = panel.frame.origin
        globe.mouseDown(with:event(.leftMouseDown,5,point:NSPoint(x:120,y:120),option:true))
        // Modifier release during a gesture must not change its meaning.
        globe.mouseDragged(with:event(.leftMouseDragged,6,point:NSPoint(x:150,y:120)))
        globe.mouseUp(with:event(.leftMouseUp,7,point:NSPoint(x:150,y:120)))
        XCTAssertEqual(panel.frame.origin,movedOrigin)
        XCTAssertGreaterThan(globe.rotation.yaw,yaw)
        XCTAssertEqual(selections,0)
        globe.mouseDown(with:event(.leftMouseDown,8,point:NSPoint(x:120,y:120)))
        globe.mouseUp(with:event(.leftMouseUp,9,point:NSPoint(x:120,y:120)))
        XCTAssertEqual(selections,1,"Click after a drag must still open the card")
        globe.mouseDown(with:event(.leftMouseDown,10,point:NSPoint(x:120,y:120)))
        globe.setRunning(false)
        let stoppedOrigin = panel.frame.origin
        globe.mouseDragged(with:event(.leftMouseDragged,11,point:NSPoint(x:180,y:120)))
        XCTAssertEqual(panel.frame.origin,stoppedOrigin,"Lifecycle interruption must cancel a pending move")
        XCTAssertFalse(globe.rotation.isDragging)
    }
}
