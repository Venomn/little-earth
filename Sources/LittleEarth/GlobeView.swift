import AppKit
import SceneKit
import EarthCore

final class GlobeView: SCNView {
    let globe = GlobeScene()
    private(set) var rotation = Rotation()
    private var lastPoint = NSPoint.zero
    private var dragStartScreenPoint = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var lastScreenPoint = NSPoint.zero
    private var dragRotates = false
    private var dragDistance: CGFloat = 0
    private var dismissedMouseDown: Int?
    private var suppressClickSelection = false
    var onSelectVessel: ((String, NSPoint) -> Void)?
    var onSelect: ((GeoCoordinate, NSPoint) -> Void)?
    private var lastDragTime: TimeInterval = 0
    private var lastTick: TimeInterval?
    private var timer: Timer?
    var onPointerUpdate: (() -> Void)?

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        scene = globe.scene
        pointOfView = globe.camera
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        rendersContinuously = false
        isPlaying = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setLanguage(.english)
        // Start at the approved art's Atlantic view, then rotate continuously.
        globe.earth.eulerAngles = SCNVector3(0.12, GlobeScene.initialYaw, -0.08)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setLanguage(_ language: AppLanguage) {
        let strings = L10n(language)
        setAccessibilityLabel(strings.text(.globeAccessibility))
        toolTip = strings.text(.globeHelp)
    }
    // Keep environment animation/rendering alive while reading a stationary globe.
    func setAutoRotationPaused(_ paused: Bool) {
        rotation.setPaused(paused)
        lastTick = nil
    }
    func setRunning(_ running: Bool) {
        timer?.invalidate(); timer = nil; lastTick = nil
        finishDrag()
        isPlaying = false
        if running {
            let t = Timer(timeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if rotation.isDragging && NSEvent.pressedMouseButtons & 1 == 0 { finishDrag() }
        if let lastTick { rotation.advance(deltaTime: now-lastTick) }
        lastTick = now
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        globe.earth.eulerAngles = SCNVector3(rotation.pitch, rotation.yaw+Double(GlobeScene.initialYaw), -0.08)
        globe.updateEnvironment()
        SCNTransaction.commit()
        setNeedsDisplay(bounds)
        onPointerUpdate?()
    }
    override func mouseDown(with event: NSEvent) {
        suppressClickSelection = dismissedMouseDown == event.eventNumber
        dismissedMouseDown = nil
        dragDistance = 0
        lastPoint = convert(event.locationInWindow, from: nil)
        dragStartScreenPoint = window?.convertPoint(toScreen:event.locationInWindow) ?? event.locationInWindow
        lastScreenPoint = dragStartScreenPoint
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        // Lock the gesture at mouse-down, even if Option changes mid-drag.
        dragRotates = event.modifierFlags.contains(.option)
        lastDragTime = event.timestamp
        rotation.beginDrag()
    }
    override func mouseDragged(with event: NSEvent) {
        guard rotation.isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let screenPoint = window?.convertPoint(toScreen:event.locationInWindow) ?? event.locationInWindow
        dragDistance += hypot(screenPoint.x-lastScreenPoint.x,screenPoint.y-lastScreenPoint.y)
        if dragRotates {
            // Scale rotation sensitivity consistently across all display sizes.
            let scale = 240 / max(1, bounds.width)
            rotation.drag(dx: (point.x-lastPoint.x)*scale, dy: (point.y-lastPoint.y)*scale,
                          deltaTime: event.timestamp-lastDragTime)
        } else if dragDistance >= 4 {
            // Screen coordinates remain stable while the window moves beneath
            // the pointer. Local deltas would otherwise feed the movement back.
            window?.setFrameOrigin(NSPoint(x:dragStartWindowOrigin.x+screenPoint.x-dragStartScreenPoint.x,
                                           y:dragStartWindowOrigin.y+screenPoint.y-dragStartScreenPoint.y))
        }
        lastScreenPoint = screenPoint
        lastPoint = point; lastDragTime = event.timestamp
    }
    override func mouseUp(with event: NSEvent) {
        guard rotation.isDragging else { return }
        if dragRotates && event.timestamp-lastDragTime > 0.12 {
            rotation.drag(dx: 0, dy: 0, deltaTime: event.timestamp-lastDragTime)
        }
        let point = convert(event.locationInWindow,from:nil)
        finishDrag()
        if dragDistance < 4 && !suppressClickSelection {
            _ = selectWeather(at:point)
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        guard isInteractive(event.locationInWindow), let menu else { return }
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    // VoiceOver and other accessibility clients can inspect the visible center
    // using the same surface picking path as an ordinary mouse click.
    override func accessibilityPerformPress() -> Bool {
        selectWeather(at:NSPoint(x:bounds.midX,y:bounds.midY))
    }
    private func selectWeather(at point: NSPoint) -> Bool {
        let selection = pick(at:point)
        if let id = selection.vesselID, let onSelectVessel {
            onSelectVessel(id,point); return true
        }
        guard let hit = selection.surface, let onSelect else { return false }
        let local = hit.localCoordinates
        onSelect(GeoCoordinate(vector:SIMD3(Double(local.x),Double(local.y),Double(local.z))),point)
        return true
    }
    private func pick(at point: NSPoint) -> (surface: SCNHitTestResult?, vesselID: String?) {
        let hits = hitTest(point,options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.sortResults:true])
        let surfaceIndex = hits.firstIndex(where: { $0.node.name == "earth-surface" }) ?? hits.endIndex
        let surface = surfaceIndex < hits.endIndex ? hits[surfaceIndex]:nil
        // Above the silhouette there may be a visible boat but no solid Earth
        // hit. Behind the solid Earth, the sorted surface still stops picking.
        if let vesselHit = hits[..<surfaceIndex].first(where: { VesselLayer.vesselID(from:$0.node) != nil }),
           let id = VesselLayer.vesselID(from:vesselHit.node) {
            return (surface,id)
        }
        return (surface,nil)
    }
    // The local event monitor closes the card before mouseDown is delivered.
    // Remember only that gesture so its mouseUp cannot immediately reopen it.
    func suppressSelection(for event: NSEvent) { dismissedMouseDown = event.eventNumber }
    func finishDrag() { rotation.endDrag() }

    func isInteractive(_ point: NSPoint) -> Bool {
        let p = convert(point, from: nil)
        if GlobeHitRegion.contains(p, in: bounds.size) { return true }
        // Only actual boat geometry can extend the interactive silhouette;
        // decorative clouds and the transparent halo still pass through.
        return bounds.contains(p) && onSelectVessel != nil && pick(at:p).vesselID != nil
    }
}
