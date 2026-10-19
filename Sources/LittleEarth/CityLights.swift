import AppKit
import SceneKit
import EarthCore
import simd

// One batched mesh: soft emissive stitches sit on the actual felt surface.
// The source supplies city anchors; tiny nearby stitches are artistic accents.
final class CityLights {
    let node: SCNNode
    let material = SCNMaterial()
    let count: Int

    init(cities: [CityLight], surfaceRadius: (GeoCoordinate) -> Float?) {
        var positions = [SCNVector3](), normals = [SCNVector3](), uv = [CGPoint](), indices = [UInt32]()
        var random = SeededRandom(state:481516)
        func stitch(at coordinate: GeoCoordinate, size: Float) {
            guard let radius = surfaceRadius(coordinate) else { return }
            let normal = SIMD3<Float>(coordinate.vector)
            let tangent = simd_normalize(simd_cross(SIMD3<Float>(0,1,0),normal))
            let vertical = simd_cross(normal,tangent)
            let center = normal * (radius + 0.004)
            let start = UInt32(positions.count)
            for (x,y): (Float,Float) in [(-1,-1),(1,-1),(1,1),(-1,1)] {
                positions.append(SCNVector3(center + tangent*x*size + vertical*y*size))
                normals.append(SCNVector3(normal)); uv.append(CGPoint(x:CGFloat((x+1)/2),y:CGFloat((y+1)/2)))
            }
            indices += [start,start+1,start+2,start,start+2,start+3]
        }
        for city in cities {
            let size = Float(0.034 + min(1,city.population/12_000_000)*0.014)
            stitch(at:city.coordinate,size:size)
            let satellites = city.population >= 1_000_000 ? 2:0
            for _ in 0..<satellites {
                let latitude = city.latitude+Double(random.next()-0.5)*2.4
                var longitude = city.longitude+Double(random.next()-0.5)*3.0/max(0.3,cos(city.latitude * .pi/180))
                if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
                let coordinate = GeoCoordinate(latitude:latitude,longitude:longitude)
                if coordinate.isValid { stitch(at:coordinate,size:size*(0.38+random.next()*0.26)) }
            }
        }
        count = positions.count/4
        let geometry = SCNGeometry(sources:[.init(vertices:positions),.init(normals:normals),.init(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = false
        material.blendMode = .alpha
        material.shaderModifiers = [.fragment:"""
        #pragma arguments
        float3 sunDirection;
        float3 globeCenter;
        #pragma transparent
        #pragma body
        float solarDot = dot(normalize(_surface.position - globeCenter), normalize(sunDirection));
        // Off at the horizon/day side; fully lit once the sun is below twilight.
        float night = 1.0 - smoothstep(-0.14, 0.0, solarDot);
        float2 p = _surface.diffuseTexcoord * 2.0 - 1.0;
        float r2 = dot(p,p);
        float core = exp(-r2*100.0);
        float halo = exp(-r2*5.0) * (1.0-smoothstep(0.55,1.0,r2));
        _output.color.rgb = mix(float3(1.0,0.63,0.25),float3(1.0,0.94,0.72),core);
        _output.color.a = clamp(core*0.98 + halo*0.34,0.0,1.0) * night;
        // SceneKit's fragment output is premultiplied for this alpha blend path.
        _output.color.rgb *= _output.color.a;
        """]
        geometry.firstMaterial = material
        node = SCNNode(geometry:geometry); node.name = "city-lights"
    }
}
