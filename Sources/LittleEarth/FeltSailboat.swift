import AppKit
import SceneKit
import simd

/// The chosen C concept: a sewn navy bowl, cream piping and one padded felt sail.
/// This is a decorative AIS marker, not a claim about the observed vessel's type.
enum FeltSailboat {
    static func make(wool: NSImage, normal: NSImage?) -> SCNNode {
        let boat = SCNNode()
        func felt(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = wool
            material.multiply.contents = NSColor(red:r,green:g,blue:b,alpha:1)
            material.normal.contents = normal
            material.normal.intensity = 0.65
            material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
            material.normal.wrapS = .repeat; material.normal.wrapT = .repeat
            material.specular.contents = NSColor.black
            material.roughness.contents = 1.0
            // Keep ivory readable under the same soft lighting as the globe, while
            // retaining the photographed fibers instead of a shiny toy surface.
            material.shaderModifiers = [.surface: """
            #pragma body
            _surface.diffuse.rgb = mix(float3(0.58), _surface.diffuse.rgb, 0.65);
            """]
            return material
        }
        let navy = felt(0.29,0.37,0.45)
        let interior = felt(0.26,0.33,0.40)
        let cream = felt(0.73,0.73,0.68)
        let ivory = felt(0.99,0.94,0.82)
        let oat = felt(0.62,0.52,0.39)
        func add(_ geometry: SCNGeometry, _ name: String, _ material: SCNMaterial,
                 at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
            geometry.firstMaterial = material
            let node = SCNNode(geometry:geometry); node.name = name; node.position = position
            boat.addChildNode(node)
            return node
        }

        // A soft elliptical bowl, with a dark inset instead of a cuboid deck/cabin.
        let hull = SCNSphere(radius:1); hull.segmentCount = 32
        let hullNode = add(hull,"felt-hull",navy,at:SCNVector3(0,0.012,0))
        hullNode.scale = SCNVector3(0.037,0.025,0.071)
        let hollow = SCNSphere(radius:1); hollow.segmentCount = 32
        let inset = add(hollow,"felt-inset",interior,at:SCNVector3(0,0.031,0))
        inset.scale = SCNVector3(0.031,0.004,0.062)
        let rim = SCNTorus(ringRadius:0.032,pipeRadius:0.003)
        rim.ringSegmentCount = 48; rim.pipeSegmentCount = 8
        let rimNode = add(rim,"cream-piping",cream,at:SCNVector3(0,0.032,0))
        rimNode.scale.z = 1.93

        let mast = SCNCapsule(capRadius:0.005,height:0.081)
        mast.radialSegmentCount = 10
        let mastNode = add(mast,"oat-mast",oat,at:SCNVector3(0,0.067,0.027))

        // A closed pillow surface has a rounded belly, not an extruded flat
        // triangle. Its gentle lean remains readable from directly overhead.
        let (sail, contour) = paddedSail()
        ivory.shaderModifiers?[.surface, default:""] += """

        float2 patchUV = (_surface.diffuseTexcoord - float2(0.73, 0.16)) / float2(0.19, 0.23);
        float patchAmount = 1.0 - smoothstep(0.85, 1.05, length(patchUV));
        _surface.diffuse.rgb *= mix(float3(1.0), float3(0.77, 0.58, 0.31), patchAmount);
        """
        let sailNode = add(sail,"padded-ivory-sail",ivory,at:SCNVector3(0,0.038,0.027))
        sailNode.eulerAngles = SCNVector3(-0.32,.pi/2 - 0.28,0)

        // Sparse sewn stitches, rather than windows or metallic fittings.
        for i in 0..<10 {
            let angle = Float(i)*2 * .pi/10
            let stitch = SCNCapsule(capRadius:0.0013,height:0.009)
            stitch.radialSegmentCount = 5
            let node = add(stitch,"hull-stitch",cream,
                           at:SCNVector3(sin(angle)*0.035,0.016,cos(angle)*0.067))
            node.eulerAngles = SCNVector3(cos(angle)*0.35,0,-sin(angle)*0.35)
        }

        // Actual fine strands soften the silhouette on close views. All boats
        // share these small meshes; no billboard/transparent rectangle hit area.
        hullNode.addChildNode(fibers(material:navy,seed:19,count:900) { rng in
            let y = rng.next()*1.8-0.9, angle = rng.next()*2 * .pi
            let radial = sqrt(1-y*y)
            let p = SIMD3<Float>(sin(angle)*radial,y,cos(angle)*radial)
            return (p,p,0.045)
        })
        sailNode.addChildNode(fibers(material:ivory,seed:71,count:900) { rng in
            let boundary = contour[Int(rng.next()*Float(contour.count)) % contour.count]
            let r = sqrt(rng.next()), side: Float = rng.next() > 0.5 ? 1:-1
            let point = sailCenter + (boundary-sailCenter)*r
            let p = SIMD3<Float>(point.x,point.y,side*sailThickness(r))
            return (p,SIMD3(0,0,side),0.0022)
        })
        rimNode.addChildNode(fibers(material:cream,seed:83,count:650) { rng in
            let a = rng.next()*2 * .pi, b = rng.next()*2 * .pi
            let n = SIMD3<Float>(cos(a)*cos(b),sin(b),sin(a)*cos(b))
            let p = SIMD3<Float>(cos(a)*0.032,0,sin(a)*0.032) + n*0.003
            return (p,n,0.0025)
        })
        mastNode.addChildNode(fibers(material:oat,seed:92,count:350) { rng in
            let a = rng.next()*2 * .pi
            let n = SIMD3<Float>(cos(a),0,sin(a))
            return (n*0.005+SIMD3(0,(rng.next()-0.5)*0.070,0),n,0.0025)
        })
        return boat
    }

    private static let sailCenter = SIMD2<Float>(0.028,0.026)
    private static func sailThickness(_ radius: Float) -> Float {
        0.002 + 0.013*sqrt(max(0,1-radius*radius))
    }
    private static func paddedSail() -> (SCNGeometry,[SIMD2<Float>]) {
        // Rounded triangular outline, sampled into concentric rings on each side.
        let corners: [(SIMD2<Float>,SIMD2<Float>,SIMD2<Float>,SIMD2<Float>)] = [
            (.init(0.008,0.002),.init(0.023,-0.001),.init(0.061,0.001),.init(0.067,0.007)),
            (.init(0.067,0.007),.init(0.073,0.014),.init(0.022,0.060),.init(0.013,0.066)),
            (.init(0.013,0.066),.init(0.006,0.073),.init(0.003,0.062),.init(0.005,0.051)),
            (.init(0.005,0.051),.init(0.004,0.028),.init(0.002,0.007),.init(0.008,0.002))]
        var contour = [SIMD2<Float>]()
        for (a,b,c,d) in corners {
            for i in 0..<16 {
                let t = Float(i)/16, q = 1-t
                let p = a*(q*q*q) + b*(3*q*q*t) + c*(3*q*t*t) + d*(t*t*t)
                contour.append(p)
            }
        }
        let count = contour.count, rings = 10
        var vertices = [SIMD3<Float>](), uv = [CGPoint](), indices = [Int32]()
        for side: Float in [1,-1] {
            let base = vertices.count
            for ring in 0...rings {
                let r = Float(ring)/Float(rings)
                for point in contour {
                    let p = sailCenter + (point-sailCenter)*r
                    vertices.append(.init(p.x,p.y,side*sailThickness(r)))
                    uv.append(CGPoint(x:Double(p.x/0.078),y:Double(p.y/0.075)))
                }
            }
            for ring in 0..<rings {
                for j in 0..<count {
                    let a = Int32(base+ring*count+j), b = Int32(base+ring*count+(j+1)%count)
                    let c = a+Int32(count), d = b+Int32(count)
                    indices += side > 0 ? [a,c,b,b,c,d] : [a,b,c,b,d,c]
                }
            }
        }
        let back = (rings+1)*count
        for j in 0..<count {
            let a = Int32(rings*count+j), b = Int32(rings*count+(j+1)%count)
            let c = a+Int32(back), d = b+Int32(back)
            indices += [a,c,b,b,c,d]
        }
        var normals = [SIMD3<Float>](repeating:.zero,count:vertices.count)
        for i in stride(from:0,to:indices.count,by:3) {
            let a = Int(indices[i]), b = Int(indices[i+1]), c = Int(indices[i+2])
            let n = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        for i in normals.indices {
            normals[i] = simd_length_squared(normals[i]) > 1e-16 ? simd_normalize(normals[i]) : SIMD3(0,0,vertices[i].z > 0 ? 1:-1)
        }
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices.map(SCNVector3.init)),
                                            SCNGeometrySource(normals:normals.map(SCNVector3.init)),
                                            SCNGeometrySource(textureCoordinates:uv)],
                                   elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        return (geometry,contour)
    }

    private static func fibers(material: SCNMaterial, seed: UInt64, count: Int,
                               sample: (inout SeededRandom) -> (SIMD3<Float>,SIMD3<Float>,Float)) -> SCNNode {
        var rng = SeededRandom(state:seed)
        var vertices = [SCNVector3](), indices = [Int32]()
        for _ in 0..<count {
            let (p,n,length) = sample(&rng)
            let axis = simd_normalize(simd_cross(n,abs(n.y) < 0.9 ? SIMD3(0,1,0):SIMD3(1,0,0)))
            let across = simd_cross(n,axis), angle = rng.next()*2 * .pi
            let tangent = axis*cos(angle) + across*sin(angle)
            let side = simd_cross(n,tangent)
            let strandLength = length*(0.45+rng.next()*1.15)
            let curl = (rng.next()-0.5)*1.2
            let start = Int32(vertices.count)
            for segment in 0...4 {
                let t = Float(segment)/4
                let lift: Float = sin(t * Float.pi)*0.38
                let bend: Float = sin(t * Float.pi*1.5)*curl
                let offset: SIMD3<Float> = tangent*t + n*lift + side*bend
                let point = p + offset*strandLength
                vertices.append(SCNVector3(point))
                if segment > 0 { indices += [start+Int32(segment)-1,start+Int32(segment)] }
            }
        }
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],
                                   elements:[SCNGeometryElement(indices:indices,primitiveType:.line)])
        let fiber = material.copy() as! SCNMaterial
        fiber.lightingModel = .constant
        fiber.transparency = 0.12
        geometry.firstMaterial = fiber
        let node = SCNNode(geometry:geometry); node.name = "wool-fibers"
        return node
    }
}
