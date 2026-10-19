import AppKit
import SceneKit
import Metal
import EarthCore
if CommandLine.arguments.count == 2, ["--vessel-service","--vessel-service-authorize"].contains(CommandLine.arguments[1]) {
    MainActor.assumeIsolated { runVesselService(allowInteraction:CommandLine.arguments[1] == "--vessel-service-authorize") }
}
let application = NSApplication.shared
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fetch-weather" {
    Task {
        let result = await WeatherClient().fetch()
        do {
            let data = try JSONEncoder().encode(WeatherSnapshot(samples:result.samples))
            try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
            print("Weather: \(result.samples.count)/\(WeatherGrid.coordinates.count), failed batches: \(result.failedBatches), usable: \(result.samples.filter { $0.usable(at:Date()) }.count)")
            exit(result.samples.isEmpty ? 2:0)
        } catch { print(error); exit(1) }
    }
    RunLoop.main.run()
    exit(1)
}
// Native card snapshots use the same controller, bundled atlas and curated content as the popover.
if CommandLine.arguments.count == 3, ["--render-culture","--render-marine"].contains(CommandLine.arguments[1]) {
    let directory = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try L10n.validateResources()
    let marinePreview = CommandLine.arguments[1] == "--render-marine"
    for language in AppLanguage.allCases {
      let strings = L10n(language)
      let stories: [(id:String,content:CultureText,sourceURL:String)]
      if marinePreview {
          stories = try MarineCatalog.bundled().entries.map { ($0.id,$0.text(in:language),$0.sourceURL) }
      } else {
          stories = try CultureCatalog.bundled().entries.map { ($0.id,$0.text(in:language),$0.sourceURL) }
      }
      for story in stories {
        let content = story.content
        let name = "\(language.rawValue)-\(story.id)"
        let controller = WeatherDetailController()
        func card(_ day: UIString) -> PlaceCard {
            PlaceCard(language:language,region:content.regionLabel,theme:content.theme,title:content.title,body:content.body,
                      weather:strings.format(.compactUnavailable,strings.text(day)),weatherDetails:strings.text(.previewNoWeather),
                      sourceName:content.sourceName,sourceURL:URL(string:story.sourceURL))
        }
        controller.update(card(.day))
        let view = controller.view
        let originalControls = view.subviews
        controller.update(card(.night))
        precondition(originalControls.count == view.subviews.count && zip(originalControls,view.subviews).allSatisfy { $0 === $1 }, "Weather refresh replaced reading controls")
        let window = NSWindow(contentRect:view.bounds,styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = view
        func save(_ suffix: String) throws {
            window.setContentSize(view.frame.size)
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("\(name)\(suffix).png"))
        }
        try save("")
        view.subviews.compactMap { $0 as? NSButton }.first!.performClick(nil)
        try save("-expanded")
        print("\(name): \(Int(view.frame.width))x\(Int(view.frame.height)) expanded")
      }
    }
    print("Bilingual native card rendering complete.")
    exit(0)
}
// Explicit visual fixtures, never used by the live companion.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-vessels" {
    let directory = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let globe = GlobeScene()
    let positions = [(15.0,-45.0,45.0),(-10.0,-20.0,130.0),(40.0,-50.0,300.0),(-30.0,-5.0,200.0)]
    let samples = positions.enumerated().map { i,p in
        VesselSample(mmsi:"99000000\(i)",name:"Visual test vessel",coordinate:GeoCoordinate(latitude:p.0,longitude:p.1),speedKnots:8,courseDegrees:p.2,headingDegrees:p.2,receivedAt:Date())
    }
    globe.applyVessels(samples)
    globe.earth.eulerAngles = SCNVector3(0,GlobeScene.initialYaw,0)
    globe.updateEnvironment()
    globe.scene.background.contents = NSColor(white:0.94,alpha:1)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = globe.scene; renderer.pointOfView = globe.camera
    for size in [700,240] {
        let render = renderer.snapshot(atTime:0,with:CGSize(width:size,height:size),antialiasingMode:.multisampling4X)
        let annotated = NSImage(size:NSSize(width:size,height:size+30))
        annotated.lockFocus()
        NSColor(white:0.94,alpha:1).setFill(); NSRect(x:0,y:0,width:size,height:size+30).fill()
        render.draw(in:NSRect(x:0,y:30,width:size,height:size))
        ("VISUAL TEST · NOT LIVE AIS" as NSString).draw(at:NSPoint(x:8,y:8),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.darkGray])
        annotated.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage:annotated.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("vessels-test-\(size).png"))
    }
    // Dense European sea fixtures exercise the production inventory selection.
    // Coordinates are synthetic test observations, never fed to the live service.
    let europeanWaters = [(60.0,-2.0),(55,3),(57,10),(54,8),(50,-2),(45,-5),
                          (38,4),(36,18),(40,15),(60,20),(65,7),(62,2),(48,-8),(35,-5)]
    var denseInventory = VesselInventory()
    let fixtureTime = Date()
    for (index, p) in europeanWaters.enumerated() {
        denseInventory.merge(VesselSample(mmsi:String(990001000 + index),name:"Density fixture",
            coordinate:GeoCoordinate(latitude:p.0,longitude:p.1),speedKnots:nil,
            courseDegrees:Double(index * 37 % 360),headingDegrees:nil,receivedAt:fixtureTime),at:fixtureTime)
    }
    globe.applyVessels(denseInventory.visible(at:fixtureTime))
    for yaw in [0.0, -0.7] {
        globe.earth.eulerAngles = SCNVector3(0,yaw,0)
        globe.updateEnvironment()
        for size in [700,180] {
            let render = renderer.snapshot(atTime:0,with:CGSize(width:size,height:size),antialiasingMode:.multisampling4X)
            let annotated = NSImage(size:NSSize(width:size,height:size+30))
            annotated.lockFocus()
            NSColor(white:0.94,alpha:1).setFill(); NSRect(x:0,y:0,width:size,height:size+30).fill()
            render.draw(in:NSRect(x:0,y:30,width:size,height:size))
            ("DENSITY TEST · NOT LIVE AIS" as NSString).draw(at:NSPoint(x:4,y:8),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.darkGray])
            annotated.unlockFocus()
            let bitmap = NSBitmapImageRep(cgImage:annotated.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("europe-\(yaw)-\(size).png"))
        }
    }
    // Inspect the real shared geometry from the side and above, not generated art.
    let modelScene = SCNScene()
    modelScene.background.contents = NSColor(red:0.92,green:0.90,blue:0.85,alpha:1)
    let model = FeltSailboat.make(wool:GlobeScene.resource("cloud-felt.png"),
                                 normal:GlobeScene.resource("cloud-felt-normal.png"))
    modelScene.rootNode.addChildNode(model)
    for (type,position,intensity) in [(SCNLight.LightType.ambient,SCNVector3Zero,350.0),(.omni,SCNVector3(-1,2,2),900.0)] {
        let light = SCNNode(); light.light = SCNLight(); light.light!.type = type; light.light!.intensity = intensity
        light.position = position; modelScene.rootNode.addChildNode(light)
    }
    let camera = SCNNode(); camera.camera = SCNCamera()
    camera.camera!.usesOrthographicProjection = true; camera.camera!.orthographicScale = 0.12
    camera.camera!.zNear = 0.01; camera.camera!.zFar = 10
    modelScene.rootNode.addChildNode(camera)
    renderer.scene = modelScene; renderer.pointOfView = camera
    for (name,position) in [("side",SCNVector3(0.35,0.23,0.3)),("above",SCNVector3(0.12,0.5,0.18))] {
        camera.position = position; camera.look(at:SCNVector3(0,0.06,0))
        let render = renderer.snapshot(atTime:0,with:CGSize(width:700,height:700),antialiasingMode:.multisampling4X)
        let annotated = NSImage(size:NSSize(width:700,height:730))
        annotated.lockFocus()
        NSColor(white:0.94,alpha:1).setFill(); NSRect(x:0,y:0,width:700,height:730).fill()
        render.draw(in:NSRect(x:0,y:30,width:700,height:700))
        ("NATIVE MODEL · VISUAL TEST · NOT LIVE AIS" as NSString).draw(at:NSPoint(x:12,y:8),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.darkGray])
        annotated.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage:annotated.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("sailboat-\(name).png"))
    }
    print("Vessel visual fixtures rendered; no live AIS data.")
    exit(0)
}
// Art QA replays a recorded real-weather snapshot at its original valid time.
// No synthetic cloud placement or changes to the user's live clock/preferences.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--render-night-study" {
    let snapshot = try WeatherSnapshot.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
    guard let date = snapshot.samples.map(\.validAt).max() else { fatalError("Empty weather snapshot") }
    let directory = URL(fileURLWithPath:CommandLine.arguments[3],isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let globe = GlobeScene()
    globe.applyWeather(snapshot.samples,at:date)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = globe.scene; renderer.pointOfView = globe.camera
    let sun = SolarPosition.coordinate(at:date)
    // Look toward local midnight; a second view faces noon for a daylight regression.
    let nightYaw = CGFloat(-sun.longitude * .pi/180 + .pi)
    for (name,yaw,background,size): (String,CGFloat,NSColor,CGFloat) in [
        ("night",nightYaw,NSColor(white:0.91,alpha:1),700),
        ("night-desktop",nightYaw,NSColor(white:0.91,alpha:1),240),
        ("night-dark",nightYaw,NSColor(white:0.13,alpha:1),700),
        ("day",nightYaw + .pi,NSColor(white:0.91,alpha:1),700),
        ("terminator",nightYaw + .pi/2,NSColor(white:0.91,alpha:1),700)] {
        globe.earth.eulerAngles = SCNVector3(0,yaw,0)
        globe.scene.background.contents = background
        globe.updateEnvironment(at:date)
        let render = renderer.snapshot(atTime:0,with:CGSize(width:size,height:size),antialiasingMode:.multisampling4X)
        let bitmap = NSBitmapImageRep(cgImage:render.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
    }
    print("Recorded real weather: \(snapshot.samples.count) samples, valid \(ISO8601DateFormatter().string(from:date)).")
    exit(0)
}
// Fixed UTC instants exercise the real geographic night shader, with no simulated weather.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-lights" {
    let directory = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let globe = GlobeScene()
    guard let cityLights = globe.cityLights else { throw CocoaError(.fileReadCorruptFile) }
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = globe.scene; renderer.pointOfView = globe.camera
    let formatter = ISO8601DateFormatter()
    func save(_ name: String, hour: Int, yaw: CGFloat, size: CGFloat = 600, lights: Bool = true) throws {
        let date = formatter.date(from:String(format:"2026-03-20T%02d:00:00Z",hour))!
        globe.earth.eulerAngles = SCNVector3(0.12,yaw,-0.08)
        cityLights.node.isHidden = !lights
        globe.updateEnvironment(at:date)
        let rendered = renderer.snapshot(atTime:0,with:CGSize(width:size,height:size),antialiasingMode:.multisampling4X)
        let bitmap = NSBitmapImageRep(cgImage:rendered.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("\(name).png"))
    }
    globe.scene.background.contents = NSColor(red:0.91,green:0.90,blue:0.87,alpha:1)
    for (name,yaw,night,day): (String,CGFloat,Int,Int) in [("asia",-1.7,16,4),("americas",0.9,4,16)] {
        try save(name+"-night",hour:night,yaw:yaw)
        try save(name+"-night-off",hour:night,yaw:yaw,lights:false)
        try save(name+"-day",hour:day,yaw:yaw)
        try save(name+"-day-off",hour:day,yaw:yaw,lights:false)
        for size: CGFloat in [180,240,330] { try save(name+"-night-\(Int(size))",hour:night,yaw:yaw,size:size) }
    }
    try save("terminator",hour:10,yaw:0.9)
    globe.scene.background.contents = NSColor(red:0.13,green:0.18,blue:0.23,alpha:1)
    try save("night-dark-background",hour:4,yaw:0.9)
    print("City light stitches: \(cityLights.count). Rendered day/night, lights on/off, terminator, dark background and desktop sizes.")
    exit(0)
}
let weatherPreview = CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--render-weather"
if weatherPreview || (CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--render-preview") {
    let directory = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let globe = GlobeScene()
    if weatherPreview {
        let snapshot = try WeatherSnapshot.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        globe.applyWeather(snapshot.samples)
    }
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = globe.scene; renderer.pointOfView = globe.camera
    func save(_ name: String, yaw: CGFloat, size: CGFloat = 800) throws {
        globe.earth.eulerAngles = SCNVector3(0.12,yaw,-0.08)
        globe.updateEnvironment()
        let rendered = renderer.snapshot(atTime: 0, with: CGSize(width: size,height: size), antialiasingMode: .multisampling4X)
        let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bytes = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
        try bytes.write(to: directory.appendingPathComponent("\(name).png"))
    }
    for (name, yaw): (String, CGFloat) in [("asia", -1.7), ("americas", GlobeScene.initialYaw), ("africa", 0.0)] {
        try save(name, yaw: yaw)
    }
    // QA backgrounds and small-size samples use the identical scene and lights.
    globe.scene.background.contents = NSColor(red: 0.91,green: 0.90,blue: 0.87,alpha: 1)
    try save("americas-cream", yaw: GlobeScene.initialYaw)
    for size: CGFloat in [180,240,330] { try save("desktop-\(Int(size))", yaw: GlobeScene.initialYaw, size: size) }
    globe.scene.background.contents = NSColor(red: 0.13,green: 0.18,blue: 0.23,alpha: 1)
    try save("americas-dark", yaw: GlobeScene.initialYaw)
    globe.scene.background.contents = NSColor.clear
    for step in 0..<12 { try save("turn-\(step)", yaw: CGFloat(step)*2 * .pi/12, size: 400) }
    exit(0)
}
MainActor.assumeIsolated {
    let delegate = CompanionController()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
