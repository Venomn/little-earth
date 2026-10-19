import Foundation

public struct Rotation {
    public private(set) var yaw: Double = 0
    public private(set) var pitch: Double = 0.12
    public private(set) var isDragging = false
    public private(set) var isPaused = false
    private var velocity: Double = 0
    private let baseSpeed = 2 * Double.pi / 120
    public init() {}
    public mutating func setPaused(_ paused: Bool) {
        isPaused = paused
        velocity = 0
    }
    public mutating func advance(deltaTime: Double) {
        guard !isDragging, !isPaused, deltaTime.isFinite, deltaTime > 0 else { return }
        let dt = min(deltaTime, 0.1)
        let decay = exp(-4 * dt)
        yaw += baseSpeed * dt + velocity * (1 - decay) / 4
        velocity *= decay
        // Retain continuity through ordinary turns; bound very long sessions.
        if abs(yaw) > 10000 { yaw.formTruncatingRemainder(dividingBy: 2 * .pi) }
    }
    public mutating func beginDrag() { isDragging = true; velocity = 0 }
    public mutating func drag(dx: Double, dy: Double, deltaTime: Double) {
        guard isDragging, dx.isFinite, dy.isFinite else { return }
        yaw += max(-1000, min(1000, dx)) * 0.009
        pitch = max(-0.65, min(0.65, pitch - dy * 0.007))
        if deltaTime.isFinite, deltaTime > 0 {
            velocity = max(-2.5, min(2.5, dx * 0.009 / max(0.016, deltaTime)))
        } else { velocity = 0 }
    }
    public mutating func endDrag() { isDragging = false }
}
