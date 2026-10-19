import AppKit
import SceneKit
import simd
import EarthCore

/// A continuous, deliberately low-detail projection of the measured cloud
/// amounts. Wool grain is only material detail; it does not invent weather.
final class CloudField {
    let node: SCNNode
    let material: SCNMaterial
    init(samples: [WeatherSample], wool: NSImage, at date: Date) {
        let width = 512, height = 256
        let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to:UInt8.self)
        let projection = RegionalWeather(samples:samples,at:date)
        // UV orientation is south-up, matching the globe's custom sphere mesh.
        for y in 0..<height { for x in 0..<width {
            let point = GeoCoordinate(latitude:Double(y)/Double(height-1)*180-90,longitude:Double(x)/Double(width-1)*360-180)
            let coverage = Float((projection.cloudCover(at:point) ?? 0)/100)
            // Thin cloud veil rather than an opaque globe-sized shell.
            let opacity = max(0,(coverage-0.18)/0.82)*0.09
            let i = (y*width+x)*4, alpha = UInt8(opacity*255)
            pixels[i] = alpha; pixels[i+1] = alpha; pixels[i+2] = alpha; pixels[i+3] = alpha
        } }
        let texture = NSImage(cgImage:context.makeImage()!,size:NSSize(width:width,height:height))
        // Same longitude convention as the body (SCNSphere's built-in UV seam differs).
        var positions = [SCNVector3](), normals = [SCNVector3](), uv = [CGPoint](), indices = [UInt32]()
        let columns = 128, rows = 64
        for y in 0...rows { for x in 0...columns {
            let u = Double(x)/Double(columns), v = Double(y)/Double(rows)
            let n = SIMD3<Float>(GeoCoordinate(latitude:90-v*180,longitude:u*360-180).vector)
            positions.append(SCNVector3(n*1.078)); normals.append(SCNVector3(n)); uv.append(CGPoint(x:u,y:1-v))
        } }
        for y in 0..<rows { for x in 0..<columns {
            let a = UInt32(y*(columns+1)+x), b = a+1, c = a+UInt32(columns+1), d = c+1
            indices += [a,c,b,b,c,d]
        } }
        let geometry = SCNGeometry(sources:[.init(vertices:positions),.init(normals:normals),.init(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        material = SCNMaterial(); material.lightingModel = .lambert
        material.diffuse.contents = wool
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(3,2,1)
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
        material.transparent.contents = texture; material.transparencyMode = .aOne
        material.isDoubleSided = false; material.writesToDepthBuffer = false
        geometry.firstMaterial = material; node = SCNNode(geometry:geometry)
    }
}
