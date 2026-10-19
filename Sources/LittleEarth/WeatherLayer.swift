import AppKit
import SceneKit
import simd
import EarthCore

final class WeatherLayer {
    let root = SCNNode()
    private struct Patch {
        let sample: WeatherSample
        let anchor: SCNNode
        let cloud: FeltCloud?
        let drops: [SCNNode]
    }
    private var patches = [Patch]()
    private let wool: NSImage
    private let tuft: NSImage
    private var field: CloudField?
    private var fieldSamples = [WeatherSample]()
    var fieldMaterial: SCNMaterial? { field?.material }
    init(cloudImage: NSImage, wool: NSImage) { self.wool = wool; self.tuft = cloudImage }

    func replace(with samples: [WeatherSample], at date: Date) {
        root.childNodes.forEach { $0.removeFromParentNode() }; patches = []
        fieldSamples = samples.filter { $0.usable(at:date) }
        field = CloudField(samples:fieldSamples,wool:wool,at:date)
        if let field { root.addChildNode(field.node) }
        // Every valid sample contributes to the thin veil and precipitation.
        // Separate thick cloud crowns at regional maxima to avoid a grid of icons.
        let candidates = fieldSamples.filter { $0.cloudCover >= 65 || $0.rainMMPerHour >= 0.1 || $0.snowCMPerHour >= 0.02 }.sorted {
            let a = $0.cloudCover + min(20,$0.rainMMPerHour*4+$0.snowCMPerHour*10)
            let b = $1.cloudCover + min(20,$1.rainMMPerHour*4+$1.snowCMPerHour*10)
            return a == b ? $0.coordinate.label < $1.coordinate.label : a > b
        }
        var crowns = [GeoCoordinate]()
        for sample in candidates where crowns.allSatisfy({ $0.distance(to:sample.coordinate) > 50 }) {
            crowns.append(sample.coordinate)
        }
        for (index,sample) in fieldSamples.enumerated() {
            let n = SIMD3<Float>(sample.coordinate.vector)
            let anchor = SCNNode(); anchor.simdPosition = n*1.10
            root.addChildNode(anchor)
            let snow = sample.snowCMPerHour >= 0.02
            let wet = sample.rainMMPerHour >= 0.1 || snow
            var cloud: FeltCloud?
            if crowns.contains(sample.coordinate) {
                let felt = FeltCloud(wool:tuft,seed:UInt64(index+1)*717,storm:wet && !snow)
                // Local x/y span the tangent plane; z points away from Earth.
                felt.node.simdOrientation = simd_quatf(from:SIMD3<Float>(0,0,1),to:n)
                let scale = Float(0.95+sample.cloudCover/100*0.20)
                felt.node.simdScale = .init(repeating:scale)
                anchor.addChildNode(felt.node); cloud = felt
            }
            var drops = [SCNNode]()
            if wet {
                let strength = snow ? sample.snowCMPerHour*4 : sample.rainMMPerHour
                let count = min(5,max(2,Int(strength)+2))
                for i in 0..<count {
                    let geometry: SCNGeometry
                    if snow { let sphere = SCNSphere(radius:0.013); sphere.segmentCount = 8; geometry = sphere }
                    else { let capsule = SCNCapsule(capRadius:0.006,height:0.042); capsule.radialSegmentCount = 7; geometry = capsule }
                    let material = SCNMaterial(); material.lightingModel = .lambert
                    material.diffuse.contents = snow ? NSColor(white:0.95,alpha:1) : NSColor(red:0.35,green:0.64,blue:0.85,alpha:1)
                    geometry.firstMaterial = material
                    let drop = SCNNode(geometry:geometry)
                    drop.name = "\(i)"; drop.simdOrientation = simd_quatf(from:SIMD3<Float>(0,1,0),to:n)
                    anchor.addChildNode(drop); drops.append(drop)
                }
            }
            patches.append(Patch(sample:sample,anchor:anchor,cloud:cloud,drops:drops))
        }
    }
    func update(at date: Date, camera: SCNNode, sun: SIMD3<Double>) {
        field?.node.isHidden = fieldSamples.contains { !$0.usable(at:date) }
        let time = date.timeIntervalSinceReferenceDate
        for patch in patches {
            let p = patch.anchor.convertPosition(SCNVector3Zero,to:camera)
            let world = patch.anchor.convertPosition(SCNVector3Zero,to:nil)
            patch.anchor.isHidden = world.z < -0.20 || !patch.sample.usable(at:date) || p.z >= 0
            guard !patch.anchor.isHidden else { continue }
            let daylight = simd_dot(patch.sample.coordinate.vector,sun)
            let transition = max(0,min(1,(daylight+0.20)/0.40))
            let day = transition*transition*(3-2*transition)
            let wet = patch.sample.rainMMPerHour >= 0.1 && patch.sample.snowCMPerHour < 0.02
            let base = wet ? SIMD3<Double>(0.78,0.81,0.86) : .init(0.98,0.96,0.90)
            let shade = base * (SIMD3<Double>(0.56,0.55,0.62) * (1-day) + .init(repeating:day))
            let color = NSColor(red:shade.x,green:shade.y,blue:shade.z,alpha:1)
            patch.cloud?.material.setValue(Float(1-day),forKey:"nightAmount")
            patch.cloud?.material.multiply.contents = color
            patch.cloud?.fiberMaterial.multiply.contents = color
            for (i,drop) in patch.drops.enumerated() {
                let phase = Float((time*(patch.sample.snowCMPerHour > 0.02 ? 0.55:1.1)+Double(i)*0.23).truncatingRemainder(dividingBy:1))
                let offset = (Double(i)-Double(patch.drops.count-1)/2)*0.034
                let position = WeatherGeometry.precipitationPosition(at:patch.sample.coordinate,progress:Double(phase),offset:offset)
                drop.simdPosition = SIMD3<Float>(position)-patch.anchor.simdPosition
                drop.opacity = CGFloat(sin(phase * .pi))*0.9
            }
        }
    }
}
