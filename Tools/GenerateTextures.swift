import AppKit
import Foundation

// Deterministic, build-time textures; no downloaded photography or runtime network.
struct RNG {
    var state: UInt64 = 7132026
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992
    }
}
let w = 2048, h = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ cg: CGImage, _ name: String) throws {
    let rep = NSBitmapImageRep(cgImage: cg)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
let mask = context(w, h)
mask.setFillColor(CGColor(gray: 0, alpha: 1))
mask.fill(CGRect(x: 0, y: 0, width: w, height: h))
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for feature in root["features"] as! [[String: Any]] {
    let geometry = feature["geometry"] as! [String: Any]
    let polygons: [[[[Double]]]]
    if geometry["type"] as? String == "Polygon" {
        polygons = [geometry["coordinates"] as! [[[Double]]]]
    } else { polygons = geometry["coordinates"] as! [[[[Double]]]] }
    for polygon in polygons {
        let path = CGMutablePath()
        for ring in polygon {
            for (i, p) in ring.enumerated() {
                let point = CGPoint(x: (p[0] + 180) / 360 * Double(w), y: (90 - p[1]) / 180 * Double(h))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        mask.addPath(path)
        mask.setFillColor(CGColor(gray: 1, alpha: 1))
        mask.drawPath(using: .eoFill)
    }
}
try save(mask.makeImage()!, "land-mask.png")
let maskBytes = mask.data!.assumingMemoryBound(to: UInt8.self)
let felt = context(w, h)
let pixels = felt.data!.assumingMemoryBound(to: UInt8.self)
let woolImage = NSImage(contentsOfFile: "Assets/wool-material.png")!
let woolCG = woolImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let wool = context(w, h)
// Macro-scale wool stays legible at the companion's 160 pt presentation size.
wool.draw(woolCG, in: CGRect(x: 0, y: -h/2, width: w, height: w))
let wp = wool.data!.assumingMemoryBound(to: UInt8.self)
func patch(_ lon: Double, _ lat: Double, _ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double) -> Double {
    exp(-pow((lon-cx)/sx, 2)-pow((lat-cy)/sy, 2))
}
func mix(_ a: [Double], _ b: [Double], _ amount: Double) -> [Double] {
    zip(a,b).map { $0 * (1-amount) + $1 * amount }
}
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let land = Double(maskBytes[i]) / 255
        let fiber = Double(wp[i])/255
        let lon = Double(x)/Double(w)*360-180
        // Bitmap rows run south-to-north in this CoreGraphics mask.
        let lat = Double(y)/Double(h)*180-90
        let variation = 0.60 + fiber * 0.70
        let ocean = [70.0, 125, 162]
        // Broad felt color regions, deliberately stylized rather than satellite imagery.
        let marbling = 0.5 + 0.25*sin(lon*0.17+sin(lat*0.23)) + 0.25*cos(lat*0.31-lon*0.08)
        var ground = mix([95,124,61], [142,161,91], marbling)
        let dry = min(1, patch(lon,lat,18,24,38,13)*0.94
                      + patch(lon,lat,48,25,19,14)*0.85
                      + patch(lon,lat,135,-25,20,12)*0.83
                      + patch(lon,lat,84,43,35,11)*0.68
                      + patch(lon,lat,-111,36,12,19)*0.64
                      + patch(lon,lat,-69,-25,5,26)*0.85
                      + patch(lon,lat,23,-24,14,10)*0.48)
        ground = mix(ground, [219,200,150], dry)
        let snow = min(1, max(0,(abs(lat)-65)/14)
                       + patch(lon,lat,-42,73,18,17)*0.9
                       + patch(lon,lat,85,31,20,4)*0.65)
        ground = mix(ground, [237,232,211], snow)
        for c in 0..<3 { pixels[i+c] = UInt8(max(0, min(255, (ocean[c] * (1-land) + ground[c] * land) * variation))) }
        pixels[i+3] = 255
    }
}
try save(felt.makeImage()!, "earth-felt.png")

let normal = context(w, h)
let np = normal.data!.assumingMemoryBound(to: UInt8.self)
func luminance(_ x: Int, _ y: Int) -> Double {
    let xx = (x + w) % w, yy = max(0, min(h-1, y))
    let i = (yy*w+xx)*4
    return Double(wp[i])
}
for y in 0..<h { for x in 0..<w {
    let i = (y*w+x)*4
    let dx = (luminance(x+1,y)-luminance(x-1,y))*0.65
    let dy = (luminance(x,y+1)-luminance(x,y-1))*0.65
    np[i] = UInt8(max(0,min(255,128-dx)))
    np[i+1] = UInt8(max(0,min(255,128-dy)))
    np[i+2] = 245; np[i+3] = 255
} }
try save(normal.makeImage()!, "felt-normal.png")

let cloud = context(1024,1024)
cloud.draw(woolCG, in: CGRect(x:0,y:0,width:1024,height:1024))
let cp = cloud.data!.assumingMemoryBound(to: UInt8.self)
for i in stride(from: 0, to: 1024*1024*4, by: 4) {
    let value = 0.35 + Double(cp[i])/255 * 0.65
    cp[i] = UInt8(250*value); cp[i+1] = UInt8(245*value); cp[i+2] = UInt8(233*value)
}
try save(cloud.makeImage()!, "cloud-felt.png")
print("Generated earth, land mask, wool normals and cloud textures in \(out.path)")
