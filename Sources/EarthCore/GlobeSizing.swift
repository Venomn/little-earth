import Foundation
import CoreGraphics

/// Sizes refer to the square viewport, including the transparent weather halo.
public enum GlobeSizing {
    public static let minimumWidth: CGFloat = 180
    public static let maximumWidth: CGFloat = 660

    public static func restoredWidth(savedGlobeSize: Double) -> CGFloat {
        guard savedGlobeSize.isFinite, savedGlobeSize > 0 else { return 240 }
        return min(maximumWidth, max(minimumWidth, CGFloat(savedGlobeSize) * 1.5))
    }

    public static func fitting(_ frame: CGRect, to screen: CGRect) -> CGRect {
        let upper = min(maximumWidth, screen.width, screen.height)
        let lower = min(minimumWidth, upper)
        let width = min(upper, max(lower, frame.width))
        return WindowPlacement.clamp(CGRect(x:frame.midX-width/2, y:frame.midY-width/2,
                                           width:width, height:width), to:screen)
    }
}
