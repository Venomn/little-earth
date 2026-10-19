import AppKit

// Derive mesh coverage and fine normals from the approved wool UV artwork so
// fluffy coastlines and physical continent relief remain aligned while rotating.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let stem = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "wool-world"
let image = NSImage(contentsOf: directory.appendingPathComponent("\(stem).png"))!
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = cg.width, h = cg.height
func context() -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ ctx: CGContext, _ name: String) throws {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
let input = context()
input.draw(cg, in: CGRect(x: 0,y: 0,width: w,height: h))
let p = input.data!.assumingMemoryBound(to: UInt8.self)
let coverage = context(), normal = context()
let m = coverage.data!.assumingMemoryBound(to: UInt8.self)
let n = normal.data!.assumingMemoryBound(to: UInt8.self)
func height(_ x: Int, _ y: Int) -> Double {
    let i = (max(0,min(h-1,y))*w+(x+w)%w)*4
    return Double(p[i])*0.3+Double(p[i+1])*0.6+Double(p[i+2])*0.1
}
for y in 0..<h { for x in 0..<w {
    let i = (y*w+x)*4
    // Warm green/beige/ivory wool is distinct from the blue dyed sea.
    let t = max(0,min(1,(Double(p[i])-Double(p[i+2])+12)/28))
    let mask = UInt8(t*t*(3-2*t)*255)
    m[i] = mask; m[i+1] = mask; m[i+2] = mask; m[i+3] = 255
    let dx = (height(x+1,y)-height(x-1,y))*2.4
    let dy = (height(x,y+1)-height(x,y-1))*2.4
    n[i] = UInt8(max(0,min(255,128-dx)))
    n[i+1] = UInt8(max(0,min(255,128-dy)))
    n[i+2] = 250; n[i+3] = 255
} }
try save(coverage,"\(stem)-mask.png")
try save(normal,"\(stem)-normal.png")
print("Generated aligned wool relief: \(w) × \(h)")
