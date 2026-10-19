import AppKit
import SceneKit
import XCTest
import simd
import EarthCore
@testable import LittleEarth

@MainActor final class VesselLayerTests: XCTestCase {
    private func layer() -> VesselLayer {
        VesselLayer(wool: NSImage(size: NSSize(width: 2, height: 2)))
    }

    private func sample(_ id: String = "123456789", latitude: Double = 0, longitude: Double = 0,
                        heading: Double? = nil, course: Double? = nil) -> VesselSample {
        VesselSample(mmsi: id, name: nil, coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                     speedKnots: nil, courseDegrees: course, headingDegrees: heading, receivedAt: Date(timeIntervalSince1970: 0))
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }

    func testNoSamplesProducesNoInventedBoats() {
        let layer = layer()
        layer.apply([])
        XCTAssertTrue(layer.root.childNodes.isEmpty)
    }

    func testCoordinatePlacesBoatOnGlobeAndUpPointsAwayFromSurface() throws {
        let layer = layer()
        layer.apply([sample(latitude: 0, longitude: 90)])
        let boat = try XCTUnwrap(layer.root.childNodes.first)
        assertVector(boat.simdPosition, SIMD3(1.03, 0, 0))
        assertVector(boat.simdConvertVector(SIMD3(0, 1, 0), to: layer.root), SIMD3(1, 0, 0))
        assertVector(boat.simdConvertVector(SIMD3(0, 0, -1), to: layer.root), SIMD3(0, 1, 0))
    }

    func testHeadingOverridesCourseAndEastIsTangentToGlobe() throws {
        let layer = layer()
        layer.apply([sample(heading: 90, course: 180)])
        let boat = try XCTUnwrap(layer.root.childNodes.first)
        assertVector(boat.simdConvertVector(SIMD3(0, 0, -1), to: layer.root), SIMD3(1, 0, 0))
        assertVector(boat.simdConvertVector(SIMD3(0, 1, 0), to: layer.root), SIMD3(0, 0, 1))
    }

    func testCourseFallbackAndUnknownDirectionStayFiniteAtPoles() throws {
        let layer = layer()
        layer.apply([sample(course: 180)])
        let boat = try XCTUnwrap(layer.root.childNodes.first)
        assertVector(boat.simdConvertVector(SIMD3(0, 0, -1), to: layer.root), SIMD3(0, -1, 0))
        layer.apply([sample(latitude: 90, heading: 511, course: .nan)])
        assertVector(boat.simdPosition, SIMD3(0, 1.03, 0))
        assertVector(boat.simdConvertVector(SIMD3(0, 0, -1), to: layer.root), SIMD3(0, 0, -1))
    }

    func testHitOnGeometryFindsVesselAndUnrelatedNodeDoesNot() throws {
        let layer = layer()
        layer.apply([sample()])
        let boat = try XCTUnwrap(layer.root.childNodes.first)
        let geometry = try XCTUnwrap(boat.childNodes.first(where: { $0.geometry != nil }))
        XCTAssertEqual(VesselLayer.vesselID(from: geometry), "123456789")
        XCTAssertEqual(VesselLayer.vesselID(from: boat), "123456789")
        XCTAssertNil(VesselLayer.vesselID(from: layer.root))
        XCTAssertNil(VesselLayer.vesselID(from: SCNNode()))
        for child in boat.childNodes {
            for material in child.geometry?.materials ?? [] {
                XCTAssertTrue(material.readsFromDepthBuffer, "Boats behind Earth must remain occluded")
            }
        }
    }

    func testUpdateReusesIdentityAndRemovesMissingVessels() throws {
        let layer = layer()
        layer.apply([sample(), sample("987654321")])
        let original = try XCTUnwrap(layer.root.childNode(withName: "vessel:123456789", recursively: false))
        layer.apply([sample(longitude: -90, heading: 270)])
        XCTAssertEqual(layer.root.childNodes.count, 1)
        XCTAssertTrue(layer.root.childNodes.first === original)
        assertVector(original.simdPosition, SIMD3(-1.03, 0, 0))
        XCTAssertTrue(original.actionKeys.isEmpty, "AIS fixes must not invent motion between observations")
        layer.apply([])
        XCTAssertTrue(layer.root.childNodes.isEmpty)
    }

    func testHorizonFadeTracksRotationAndDoesNotChangeAISPositionOrHeading() throws {
        let layer = layer(), scene = SCNScene(), camera = SCNNode()
        scene.rootNode.addChildNode(layer.root); scene.rootNode.addChildNode(camera)
        camera.position = SCNVector3(0,0,6)
        layer.apply([sample(heading:45)])
        let boat = try XCTUnwrap(layer.root.childNodes.first)
        let position = boat.simdPosition, orientation = boat.simdOrientation
        layer.updateVisibility(camera:camera)
        XCTAssertEqual(boat.opacity,1,accuracy:0.001)
        layer.root.eulerAngles.y = CGFloat(acos(0.40))
        layer.updateVisibility(camera:camera)
        XCTAssertEqual(boat.opacity,0.5,accuracy:0.01)
        XCTAssertNotNil(VesselLayer.vesselID(from:boat))
        layer.root.eulerAngles.y = .pi/2
        layer.updateVisibility(camera:camera)
        XCTAssertTrue(boat.isHidden)
        XCTAssertNil(VesselLayer.vesselID(from:boat))
        layer.root.eulerAngles.y = .pi
        layer.updateVisibility(camera:camera)
        XCTAssertTrue(boat.isHidden)
        layer.root.eulerAngles.y = 0
        layer.updateVisibility(camera:camera)
        XCTAssertFalse(boat.isHidden)
        XCTAssertEqual(boat.opacity,1,accuracy:0.001)
        assertVector(boat.simdPosition,position)
        XCTAssertEqual(boat.simdOrientation,orientation)
    }

    func testInvalidCoordinateDoesNotCreateOrRetainBoat() {
        let layer = layer()
        layer.apply([sample()])
        layer.apply([sample(latitude: .nan)])
        XCTAssertTrue(layer.root.childNodes.isEmpty)
    }
}
