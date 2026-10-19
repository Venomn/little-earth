import AppKit
import SceneKit
import XCTest
import EarthCore
@testable import LittleEarth

@MainActor final class VesselInteractionTests: XCTestCase {
    func testPickingSelectsFrontShipButNotShipBehindEarth() throws {
        _ = NSApplication.shared
        let window = CompanionPanel(contentRect:NSRect(x:60,y:60,width:240,height:240),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let globe = GlobeView(frame:NSRect(x:0,y:0,width:240,height:240))
        window.contentView = globe; window.orderFrontRegardless()
        defer { window.close() }
        guard window.windowNumber > 0 else { throw XCTSkip("Requires WindowServer") }
        func sample(longitude: Double) -> VesselSample {
            VesselSample(mmsi:"123456789",name:"Test fixture",coordinate:GeoCoordinate(latitude:0,longitude:longitude),speedKnots:nil,courseDegrees:nil,headingDegrees:nil,receivedAt:Date())
        }
        var ids = [String](), surfaceSelections = 0
        globe.onSelectVessel = { id,_ in ids.append(id) }
        globe.onSelect = { _,_ in surfaceSelections += 1 }
        globe.globe.applyVessels([sample(longitude:0)])
        globe.layoutSubtreeIfNeeded(); _ = globe.snapshot()
        let projected = globe.projectPoint(globe.globe.earth.convertPosition(SCNVector3(0,0,1.05),to:nil))
        let point = NSPoint(x:CGFloat(projected.x),y:CGFloat(projected.y))
        func click(at target: NSPoint? = nil) {
            let eventPoint = target ?? point
            let down = NSEvent.mouseEvent(with:.leftMouseDown,location:eventPoint,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let up = NSEvent.mouseEvent(with:.leftMouseUp,location:eventPoint,modifierFlags:[],timestamp:1.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!
            globe.mouseDown(with:down); globe.mouseUp(with:up)
        }
        click()
        XCTAssertEqual(ids,["123456789"])
        XCTAssertEqual(surfaceSelections,0)
        globe.globe.applyVessels([sample(longitude:180)])
        _ = globe.snapshot()
        click()
        XCTAssertEqual(ids.count,1,"Back-side geometry must not steal a front-side selection")
        XCTAssertEqual(surfaceSelections,1)
        globe.globe.applyVessels([])
        _ = globe.snapshot()
        click()
        XCTAssertEqual(surfaceSelections,2)
        let local = globe.globe.earth.convertVector(SCNVector3(1,0,0),from:nil)
        let edgeCoordinate = GeoCoordinate(vector:SIMD3(Double(local.x),Double(local.y),Double(local.z)))
        let edgeSample = VesselSample(mmsi:"123456789",name:"Edge fixture",coordinate:edgeCoordinate,speedKnots:nil,courseDegrees:nil,headingDegrees:nil,receivedAt:Date())
        globe.globe.applyVessels([edgeSample]); _ = globe.snapshot()
        let boat = try XCTUnwrap(globe.globe.earth.childNode(withName:"vessel:123456789",recursively:true))
        let edgeProjection = globe.projectPoint(boat.convertPosition(SCNVector3(0.005,0.045,0.015),to:nil))
        let edgePoint = NSPoint(x:CGFloat(edgeProjection.x),y:CGFloat(edgeProjection.y))
        let edgeHits = globe.hitTest(edgePoint,options:[.searchMode:SCNHitTestSearchMode.all.rawValue])
        XCTAssertTrue(boat.isHidden,"Boats at the horizon must disappear before their masts form spikes")
        XCTAssertFalse(edgeHits.contains { VesselLayer.vesselID(from:$0.node) != nil })
        XCTAssertFalse(edgeHits.contains { $0.node.name == "earth-surface" },"Fixture must target visible ship geometry outside the solid globe")
        XCTAssertFalse(globe.isInteractive(edgePoint),"Faded edge ships must not leave an invisible click target")
        click(at:edgePoint)
        XCTAssertEqual(ids.count,1)

    }
    func testBilingualCardReportsUnknownMotionAndReceptionTimeHonestly() {
        let sample = VesselSample(mmsi:"123456789",name:nil,coordinate:GeoCoordinate(latitude:0,longitude:-30),speedKnots:nil,courseDegrees:nil,headingDegrees:nil,receivedAt:Date())
        for language in AppLanguage.allCases {
            let strings = L10n(language)
            let card = VesselCard.make(sample,language:language,weather:"weather fixture",weatherDetails:"details fixture")
            XCTAssertEqual(card.title,strings.text(.shipsUnnamed))
            XCTAssertTrue(card.body.contains(strings.text(.shipsUnknown)))
            XCTAssertTrue(card.body.contains(strings.format(.shipsReceived,strings.date(sample.receivedAt))))
            XCTAssertFalse(card.body.contains("0.0°"))
            XCTAssertEqual(card.weatherDetails,"details fixture")
            XCTAssertEqual(card.sourceURL?.host,"www.aisstream.io")
        }
    }
}
