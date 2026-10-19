import Foundation
import CoreGraphics
public enum WindowPlacement {
    public static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return CGRect(x: max(screen.minX, min(frame.minX, screen.maxX-size.width)),
                      y: max(screen.minY, min(frame.minY, screen.maxY-size.height)),
                      width: size.width, height: size.height)
    }
}
