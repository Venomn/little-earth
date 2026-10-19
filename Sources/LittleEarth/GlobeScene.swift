import AppKit
import SceneKit
import simd
import EarthCore

struct SeededRandom {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(state >> 11) / 9007199254740992)
    }
}

private struct TexturePixels {
    let width: Int, height: Int
    let bytes: [UInt8]
    init(_ image: NSImage) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        width = cg.width; height = cg.height
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: width*height*4))
    }
    func sample(u: Float, v: Float) -> SIMD3<Float> {
        let x = max(0, min(width-1, Int(u * Float(width-1))))
        let y = max(0, min(height-1, Int(v * Float(height-1))))
        let i = (y*width+x)*4
        return SIMD3(Float(bytes[i]), Float(bytes[i+1]), Float(bytes[i+2])) / 255
    }
}

final class GlobeScene {
    static let initialYaw: CGFloat = 0.9
    let scene = SCNScene()
    let earth = SCNNode()
    let camera = SCNNode()
    private(set) var cityLights: CityLights!
    private lazy var vesselLayer = VesselLayer(wool:Self.resource("cloud-felt.png"),normal:Self.resource("cloud-felt-normal.png"))
    private var dayNightMaterials = [SCNMaterial]()
    private lazy var weatherLayer = WeatherLayer(cloudImage:Self.resource("wool-tuft-v3.png"),wool:Self.resource("cloud-felt.png"))

    init() {
        scene.background.contents = NSColor.clear
        camera.camera = SCNCamera()
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = GlobeHitRegion.orthographicScale
        camera.camera!.zNear = 0.1
        camera.camera!.zFar = 30
        camera.position = SCNVector3(0, 0, 6)
        camera.camera!.wantsHDR = false
        scene.rootNode.addChildNode(camera)
        scene.rootNode.addChildNode(earth)
        addGroundShadow()
        earth.addChildNode(weatherLayer.root)
        earth.addChildNode(vesselLayer.root)

        let diffuse = Self.resource("wool-world-v3.png")
        let normal = Self.resource("cloud-felt-normal.png")
        let mask = TexturePixels(Self.resource("wool-world-v3-mask.png"))
        let colors = TexturePixels(diffuse)
        let body = SCNNode(geometry: Self.sphere(mask: mask))
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = diffuse
        material.diffuse.wrapS = .repeat
        material.normal.contents = normal
        material.normal.intensity = 0.50
        material.normal.contentsTransform = SCNMatrix4MakeScale(3,1.5,1)
        material.normal.wrapS = .repeat; material.normal.wrapT = .repeat
        material.setValue(SCNMaterialProperty(contents:Self.resource("cloud-felt.png")),forKey:"feltTexture")
        material.specular.contents = NSColor(white: 0.025, alpha: 1)
        material.shininess = 0.1
        // Lift the blue dyed wool toward the reference's dusty denim palette,
        // preserving darker cavities and the warm colors of the land fibers.
        material.shaderModifiers = [.surface: """
        #pragma arguments
        texture2d<float> feltTexture;
        #pragma body
        constexpr sampler feltSampler(coord::normalized, address::repeat, filter::linear);
        float2 uv = _surface.diffuseTexcoord;
        float3 base = float3(0.0);
        // Keep geography/color at its broad scale. Actual fine wool comes from
        // a separate fiber material instead of magnifying the coarse atlas loops.
        for (int y=-1; y<=1; ++y) { for (int x=-1; x<=1; ++x) {
            base += u_diffuseTexture.sample(feltSampler,uv + float2(x*0.0015,y*0.003)).rgb / 9.0;
        }}
        base = mix(base,_surface.diffuse.rgb,0.28);
        float grain = feltTexture.sample(feltSampler,uv * float2(3.0,1.5)).r;
        float sea = smoothstep(0.02,0.16,base.b-base.r);
        base = mix(base,pow(max(base,float3(0.001)),float3(0.68)),sea*0.85);
        _surface.diffuse.rgb = base * mix(0.78,1.19,smoothstep(0.12,0.78,grain));
        """]
        material.shaderModifiers?[.fragment] = Self.nightShader + """

        // Larger curls remain legible at desktop size under the night fill.
        // The same wool texture supplies material detail, not invented geography.
        constexpr sampler nightFeltSampler(coord::normalized, address::repeat, filter::linear);
        float nightGrain = feltTexture.sample(nightFeltSampler, _surface.diffuseTexcoord * float2(1.2, 0.6)).r;
        float fiberRelief = mix(0.68, 1.42, smoothstep(0.16, 0.58, nightGrain));
        _output.color.rgb *= mix(fiberRelief, 1.0, day);
        """
        dayNightMaterials.append(material)
        body.name = "earth-surface"
        body.geometry!.firstMaterial = material
        earth.addChildNode(body)
        let fuzz = Self.fibers(count: 26000, radius: 1, length: 0.023, seed: 27, colors: colors, mask: mask)
        if let fur = fuzz.geometry?.firstMaterial {
            let original = fur.shaderModifiers?[.fragment] ?? ""
            // Let a little more fiber catch the soft night fill across the face,
            // while retaining the original daytime silhouette treatment.
            let nightFibers = original.replacingOccurrences(of:"float edge = 0.08",with:"float fiberNight = 1.0 - smoothstep(-0.20, 0.20, dot(normalize(_surface.position - globeCenter), normalize(sunDirection)));\nfloat edge = mix(0.08, 0.34, fiberNight)")
            fur.shaderModifiers?[.fragment] = Self.nightArguments + nightFibers + "\n" + Self.nightBody
            dayNightMaterials.append(fur)
        }
        earth.addChildNode(fuzz)

        do {
            let cities = try CityLightCatalog.bundled().cities
            cityLights = CityLights(cities:cities) { coordinate in
                let u = Float(coordinate.longitude/360+0.5), v = Float(0.5-coordinate.latitude/180)
                // Exclude blue felt and shore edges, including decorative satellite stitches.
                guard mask.sample(u:u,v:1-v).x > 0.45 else { return nil }
                return Self.surfaceRadius(u:u,v:v,mask:mask)
            }
            earth.addChildNode(cityLights.node)
            dayNightMaterials.append(cityLights.material)
        } catch { NSLog("City light data unavailable: %@",String(describing:error)) }

        light(type: .ambient, color: NSColor(red: 0.84, green: 0.89, blue: 1, alpha: 1), intensity: 340, at: SCNVector3Zero)
        light(type: .omni, color: NSColor(red: 1, green: 0.96, blue: 0.88, alpha: 1), intensity: 950, at: SCNVector3(-3, 4, 5))
        light(type: .omni, color: NSColor(red: 0.72, green: 0.85, blue: 1, alpha: 1), intensity: 170, at: SCNVector3(3, -1, 3))
        light(type: .omni, color: NSColor(red: 1, green: 0.94, blue: 0.84, alpha: 1), intensity: 180, at: SCNVector3(1, 3, -3))
    }

    private func addGroundShadow() {
        let size = 256
        let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),
                                  colors:[CGColor(gray:0.12,alpha:0.20),CGColor(gray:0.12,alpha:0.08),CGColor(gray:0.12,alpha:0)] as CFArray,
                                  locations:[0,0.4,1])!
        context.drawRadialGradient(gradient,startCenter:.init(x:128,y:128),startRadius:0,
                                   endCenter:.init(x:128,y:128),endRadius:128,options:[])
        let plane = SCNPlane(width:1.8,height:0.30)
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSImage(cgImage:context.makeImage()!,size:.init(width:size,height:size))
        material.writesToDepthBuffer = false; plane.firstMaterial = material
        let shadow = SCNNode(geometry:plane); shadow.position = SCNVector3(0,-1.11,-0.4)
        scene.rootNode.addChildNode(shadow)
    }

    static func resource(_ name: String) -> NSImage {
        let resourceBundle: Bundle?
        if Bundle.main.bundleURL.pathExtension == "app" {
            resourceBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("LittleEarth_LittleEarth.bundle")) }
        } else { resourceBundle = .module }
        guard let url = resourceBundle?.url(forResource: name, withExtension: nil, subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing bundled texture: \(name). Run scripts/build-app.sh.")
        }
        return image
    }

    private func light(type: SCNLight.LightType, color: NSColor, intensity: CGFloat, at position: SCNVector3) {
        let node = SCNNode()
        node.light = SCNLight(); node.light!.type = type
        node.light!.color = color; node.light!.intensity = intensity
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private static func direction(u: Float, v: Float) -> SIMD3<Float> {
        let lon = (u - 0.5) * 2 * Float.pi
        let lat = (0.5 - v) * Float.pi
        return SIMD3(sin(lon)*cos(lat), sin(lat), cos(lon)*cos(lat))
    }

    private static func surfaceRadius(u: Float, v: Float, mask: TexturePixels) -> Float {
        var coverage: Float = 0
        for du: Float in [-0.006,-0.003,0,0.003,0.006] { for dv: Float in [-0.006,-0.003,0,0.003,0.006] {
            coverage += mask.sample(u:u+du,v:1-v+dv).x
        } }
        let n = direction(u:u,v:v)
        let tuft = 0.003 * sin(n.x*31+sin(n.y*19)) * cos(n.z*27)
        return 1 + coverage/25*0.048 + tuft
    }

    private static func sphere(mask: TexturePixels) -> SCNGeometry {
        let columns = 512, rows = 256
        var positions = [SCNVector3](), normals = [SCNVector3](), uv = [CGPoint](), indices = [UInt32]()
        func surface(_ u: Float, _ v: Float) -> SIMD3<Float> {
            let u = u - floor(u), v = max(0.0001,min(0.9999,v))
            return direction(u:u,v:v) * surfaceRadius(u:u,v:v,mask:mask)
        }
        for y in 0...rows { for x in 0...columns {
            let u = Float(x)/Float(columns), v = Float(y)/Float(rows)
            let p = direction(u: u, v: v)
            let e: Float = 0.002
            let tangent = surface(u+e,v)-surface(u-e,v)
            let bitangent = surface(u,v+e)-surface(u,v-e)
            let cross = simd_cross(bitangent,tangent)
            let normal = simd_length(cross) > 0.000001 ? simd_normalize(cross) : p
            positions.append(SCNVector3(surface(u,v))); normals.append(SCNVector3(normal)); uv.append(CGPoint(x: CGFloat(u), y: CGFloat(1-v)))
        } }
        for y in 0..<rows { for x in 0..<columns {
            let a = UInt32(y*(columns+1)+x), b = a+1, c = a+UInt32(columns+1), d = c+1
            indices += [a,c,b,b,c,d]
        } }
        return SCNGeometry(sources: [.init(vertices: positions), .init(normals: normals), .init(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    private static func fibers(count: Int, radius: Float, length: Float, seed: UInt64,
                               colors: TexturePixels? = nil, mask: TexturePixels? = nil) -> SCNNode {
        var rng = SeededRandom(state: seed)
        var positions = [SCNVector3](), normals = [SCNVector3](), rgba = [Float](), indices = [UInt32]()
        for _ in 0..<count {
            let u = rng.next(), v = acos(1 - 2*rng.next()) / Float.pi
            let n = direction(u: u, v: v)
            let tangent = simd_normalize(simd_cross(n, abs(n.y) > 0.9 ? SIMD3<Float>(1,0,0) : SIMD3<Float>(0,1,0)))
            let bitangent = simd_cross(n, tangent)
            let angle = rng.next() * 2 * Float.pi
            let t = tangent*cos(angle)+bitangent*sin(angle)
            let r = radius + (mask?.sample(u: u, v: 1-v).x ?? 0) * 0.048
            let l = length * (0.5 + rng.next())
            let color = colors?.sample(u: u, v: 1-v) ?? SIMD3<Float>(0.95,0.92,0.86)
            let shade = 0.9 + rng.next()*0.22
            let start = UInt32(positions.count)
            for step in 0...9 {
                let f = Float(step)/9
                let phase = f * 2 * Float.pi
                let lift = n * (r + 0.001 + l*sin(f * Float.pi)*0.3)
                let along = t * (l * (f + sin(phase)*0.28))
                let curl = bitangent * ((1-cos(phase))*l*0.24)
                let p = lift + along + curl
                positions.append(SCNVector3(p)); normals.append(SCNVector3(n))
                rgba += [min(1,color.x*shade*0.76+0.22),min(1,color.y*shade*0.76+0.21),min(1,color.z*shade*0.76+0.19),0.13-f*0.10]
            }
            for step in 0..<9 { indices += [start+UInt32(step),start+UInt32(step+1)] }
        }
        let colorData = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: positions.count,
                                           usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                           dataOffset: 0, dataStride: 16)
        let geometry = SCNGeometry(sources: [.init(vertices: positions), .init(normals: normals), colorSource],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.transparencyMode = .aOne
        material.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        float edge = 0.08 + 0.92 * pow(1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view))), 2.0);
        _output.color *= edge;
        """]
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private static let nightArguments = """
    #pragma arguments
    float3 sunDirection;
    float3 globeCenter;
    """ + "\n"
    private static let nightBody = """
    float solarDot = dot(normalize(_surface.position - globeCenter), normalize(sunDirection));
    float day = smoothstep(-0.20, 0.20, solarDot);
    // Night is dusty dyed wool: reduce chroma before applying a cool fill.
    // Multiplying the original blue by a blue tint made it look cobalt instead.
    float luminance = dot(_output.color.rgb, float3(0.2126, 0.7152, 0.0722));
    float3 nightWool = mix(float3(luminance), _output.color.rgb, 0.54) * float3(0.22, 0.25, 0.29);
    _output.color.rgb = mix(nightWool, _output.color.rgb, day);
    """
    private static var nightShader: String { nightArguments + "#pragma body\n" + nightBody }

    func applyVessels(_ samples: [VesselSample]) { vesselLayer.apply(samples); vesselLayer.updateVisibility(camera:camera) }

    func applyWeather(_ samples: [WeatherSample], at date: Date = Date()) {
        weatherLayer.replace(with:samples,at:date)
        weatherLayer.fieldMaterial?.shaderModifiers = [.fragment:Self.nightShader + "\n_output.color.a *= pow(abs(dot(normalize(_surface.normal), normalize(_surface.view))), 3.0);"]
        updateEnvironment(at:date)
    }
    func updateEnvironment(at date: Date = Date()) {
        let sun = SolarPosition.coordinate(at:date).vector
        let direction = earth.convertVector(SCNVector3(SIMD3<Float>(sun)),to:camera)
        let center = earth.convertPosition(SCNVector3Zero,to:camera)
        for material in dayNightMaterials + [weatherLayer.fieldMaterial].compactMap({ $0 }) {
            material.setValue(NSValue(scnVector3:direction),forKey:"sunDirection")
            material.setValue(NSValue(scnVector3:center),forKey:"globeCenter")
        }
        weatherLayer.update(at:date,camera:camera,sun:sun)
        vesselLayer.updateVisibility(camera:camera)
    }
}
