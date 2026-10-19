import XCTest
@testable import EarthCore

final class InteractionTests: XCTestCase {
    func testTransparentHaloDoesNotCaptureDesktopClicksAtEverySize() {
        for width in [180.0,240,330] {
            let size = CGSize(width: width,height: width)
            XCTAssertTrue(GlobeHitRegion.contains(CGPoint(x:width/2,y:width/2), in:size))
            XCTAssertTrue(GlobeHitRegion.contains(CGPoint(x:width*0.8,y:width/2), in:size))
            XCTAssertFalse(GlobeHitRegion.contains(CGPoint(x:width/2,y:width*0.92), in:size))
            XCTAssertFalse(GlobeHitRegion.contains(CGPoint(x:width/2,y:width*0.08), in:size))
            XCTAssertFalse(GlobeHitRegion.contains(CGPoint(x:0,y:0), in:size))
        }
    }
    func testReadingPauseStopsSpinAndInertiaButStillAllowsManualDrag() {
        var r = Rotation()
        r.beginDrag(); r.drag(dx:80,dy:10,deltaTime:0.02); r.endDrag()
        r.setPaused(true)
        let stopped = r.yaw
        for _ in 0..<300 { r.advance(deltaTime:1.0/30) }
        XCTAssertEqual(r.yaw,stopped)
        r.beginDrag(); r.drag(dx:20,dy:0,deltaTime:0.02); r.endDrag()
        XCTAssertGreaterThan(r.yaw,stopped)
        let moved = r.yaw
        r.advance(deltaTime:1)
        XCTAssertEqual(r.yaw,moved)
        r.setPaused(false)
        r.advance(deltaTime:1.0/30)
        XCTAssertEqual(r.yaw-moved,2 * .pi/120/30,accuracy:0.000001)
    }
    func testOneTurnTakes120Seconds() {
        var r = Rotation()
        for _ in 0..<3600 { r.advance(deltaTime: 1.0 / 30) }
        XCTAssertEqual(r.yaw, 2 * .pi, accuracy: 0.0001)
    }
    func testDragSuspendsAutoRotationAndReleaseIsContinuous() {
        var r = Rotation()
        r.beginDrag()
        r.drag(dx: 50, dy: 12, deltaTime: 0.1)
        let afterDrag = r.yaw
        XCTAssertGreaterThan(afterDrag, 0.2)
        r.advance(deltaTime: 0.03)
        XCTAssertEqual(r.yaw, afterDrag)
        r.endDrag()
        XCTAssertEqual(r.yaw, afterDrag)
        for _ in 0..<120 { r.advance(deltaTime: 1.0 / 30) }
        let settled = r.yaw
        for _ in 0..<30 { r.advance(deltaTime: 1.0 / 30) }
        XCTAssertEqual(r.yaw - settled, 2 * .pi / 120, accuracy: 0.001)
    }
    func testExtremeDragIsClampedAndInvalidInputIsIgnored() {
        var r = Rotation()
        r.beginDrag()
        r.drag(dx: 10, dy: 100000, deltaTime: 0)
        XCTAssertLessThanOrEqual(abs(r.pitch), 0.65)
        let yaw = r.yaw
        r.drag(dx: .infinity, dy: .nan, deltaTime: .nan)
        XCTAssertEqual(r.yaw, yaw)
        XCTAssertTrue(r.pitch.isFinite)
    }
    func testWakeDoesNotFastForwardAndInvalidDeltaDoesNothing() {
        var r = Rotation()
        r.advance(deltaTime: 3600)
        XCTAssertGreaterThan(r.yaw, 0)
        XCTAssertLessThan(r.yaw, 0.01)
        let yaw = r.yaw
        for dt in [-1.0, Double.nan, Double.infinity] { r.advance(deltaTime: dt) }
        XCTAssertEqual(r.yaw, yaw)
    }
    func testStationaryReleaseDoesNotRetainEarlierFling() {
        var r = Rotation()
        r.beginDrag()
        r.drag(dx: 60, dy: 0, deltaTime: 0.02)
        r.drag(dx: 0, dy: 0, deltaTime: 0.2)
        r.endDrag()
        let yaw = r.yaw
        r.advance(deltaTime: 1.0 / 30)
        XCTAssertLessThan(r.yaw - yaw, 0.01)
    }
    func testWindowRestoresOnNegativeCoordinateScreen() {
        let screen = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let frame = CGRect(x: 2000, y: -500, width: 260, height: 300)
        let result = WindowPlacement.clamp(frame, to: screen)
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.size, frame.size)
    }
    func testOversizedWindowFitsSmallScreen() {
        let screen = CGRect(x: 0, y: 0, width: 200, height: 250)
        XCTAssertTrue(screen.contains(WindowPlacement.clamp(CGRect(x: -10, y: 0, width: 500, height: 500), to: screen)))
    }
}
