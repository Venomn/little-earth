import AppKit
import SceneKit
import simd

/// Overlapping fiber tufts distributed in a 3D volume. Each small tuft faces the
/// camera, while its center remains attached to the rotating geographic anchor.
/// This preserves the photographed fiber silhouette without a single flat icon.
final class FeltCloud {
    let node = SCNNode()
    let material: SCNMaterial
    let fiberMaterial: SCNMaterial
    init(wool: NSImage, seed: UInt64, storm: Bool) {
        var rng = SeededRandom(state:seed)
        material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = wool
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.transparencyMode = .aOne
        material.shaderModifiers = [.surface:"""
        #pragma arguments
        float nightAmount;
        #pragma body
        // Neutralize the photographed cream fibers under cool night fill.
        // Preserve their highlights and cavities instead of flattening the tuft.
        float gray = dot(_surface.diffuse.rgb, float3(0.2126, 0.7152, 0.0722));
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(gray), nightAmount * 0.78);
        """]
        material.setValue(Float(0),forKey:"nightAmount")
        fiberMaterial = material
        // A loose, asymmetrical silhouette instead of four identical crowns.
        let lobes: [(SIMD3<Float>,Float)] = [
            (.init(-0.095,-0.012,0),0.175),(.init(0.035,0.020,0.024),0.19),
            (.init(0.135,-0.028,0.012),0.12)]
        let spread = 0.78+rng.next()*0.40
        for (center,radius) in lobes {
            let diameter = radius*2*(0.78+rng.next()*0.30)
            let plane = SCNPlane(width:CGFloat(diameter),height:CGFloat(diameter*(0.78+rng.next()*0.22)))
            plane.firstMaterial = material
            let tuft = SCNNode(geometry:plane)
            tuft.eulerAngles.z = CGFloat((rng.next()-0.5)*1.1)
            let facing = SCNNode()
            facing.simdPosition = center*spread + SIMD3<Float>((rng.next()-0.5)*0.045,(rng.next()-0.5)*0.04,(rng.next()-0.5)*0.025)
            let billboard = SCNBillboardConstraint(); billboard.freeAxes = .all
            facing.constraints = [billboard]
            facing.addChildNode(tuft)
            node.addChildNode(facing)
        }
    }
}
