import CoreGraphics

public enum GlobeHitRegion {
    public static let orthographicScale: Double = 1.42
    public static func contains(_ point: CGPoint, in viewport: CGSize) -> Bool {
        guard viewport.width > 0, viewport.height > 0,
              point.x.isFinite, point.y.isFinite else { return false }
        let radius = min(viewport.width, viewport.height) / (2 * orthographicScale) * 1.04
        let dx = point.x - viewport.width/2, dy = point.y - viewport.height/2
        return dx*dx + dy*dy <= radius*radius
    }
}
