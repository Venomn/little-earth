import AppKit
import EarthCore
import SceneKit
import simd

/// Observed AIS fixes only. The layer owns presentation, never extrapolated positions.
final class VesselLayer {
    let root = SCNNode()
    private var vessels = [String: SCNNode]()
    private let model: SCNNode

    init(wool: NSImage, normal: NSImage? = nil) {
        model = FeltSailboat.make(wool: wool, normal: normal)
        root.name = "vessels"
    }

    func apply(_ samples: [VesselSample]) {
        var present = Set<String>()
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        for sample in samples where sample.coordinate.isValid && !sample.mmsi.isEmpty {
            present.insert(sample.mmsi)
            let boat: SCNNode
            if let existing = vessels[sample.mmsi] {
                boat = existing
            } else {
                boat = makeBoat(id: sample.mmsi)
                vessels[sample.mmsi] = boat
                root.addChildNode(boat)
            }

            let latitude = Float(sample.coordinate.latitude * .pi / 180)
            let longitude = Float(sample.coordinate.longitude * .pi / 180)
            let up = SIMD3<Float>(sample.coordinate.vector)
            // Analytic tangents stay finite at the poles, where a cross with world-up would not.
            let north = SIMD3<Float>(-sin(latitude) * sin(longitude), cos(latitude), -sin(latitude) * cos(longitude))
            let east = SIMD3<Float>(cos(longitude), 0, -sin(longitude))
            let bearing = [sample.headingDegrees, sample.courseDegrees].compactMap { value -> Double? in
                guard let value, value.isFinite, (0..<360).contains(value) else { return nil }
                return value
            }.first ?? 0
            let angle = Float(bearing * .pi / 180)
            let forward = north * cos(angle) + east * sin(angle)
            let right = simd_cross(forward, up)
            // Local -Z is the bow, +Y is out of the sea, and +X is starboard.
            boat.simdOrientation = simd_quatf(simd_float3x3(columns: (right, up, -forward)))
            boat.simdPosition = up * 1.03
        }
        for id in Array(vessels.keys) where !present.contains(id) {
            vessels.removeValue(forKey: id)?.removeFromParentNode()
        }
    }

    /// Fade before the horizon so radial masts cannot form a spiky silhouette.
    /// Geographic position and AIS heading remain unchanged as the camera moves.
    func updateVisibility(camera: SCNNode) {
        let center = root.convertPosition(SCNVector3Zero,to:camera)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for boat in vessels.values {
            let p = boat.convertPosition(SCNVector3Zero,to:camera)
            let direction = SIMD3<Float>(Float(p.x-center.x),Float(p.y-center.y),Float(p.z-center.z))
            let facing = simd_normalize(direction).z
            let t = max(0,min(1,(facing-0.24)/0.32))
            boat.opacity = CGFloat(t*t*(3-2*t))
            boat.isHidden = t <= 0
        }
        SCNTransaction.commit()
    }

    static func vesselID(from node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let candidate = current {
            guard !candidate.isHidden, candidate.opacity > 0.15 else { return nil }
            if let name = candidate.name, name.hasPrefix("vessel:") {
                let id = String(name.dropFirst("vessel:".count))
                return id.isEmpty ? nil : id
            }
            current = candidate.parent
        }
        return nil
    }

    private func makeBoat(id: String) -> SCNNode {
        // Clones share immutable geometry/materials; AIS updates only move their anchor.
        let boat = model.clone()
        boat.name = "vessel:\(id)"
        return boat
    }
}
