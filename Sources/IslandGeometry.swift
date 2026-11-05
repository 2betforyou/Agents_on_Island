import Foundation

/// Shared dimensions for the floating surface, its host window, and pointer tracking.
enum IslandMetrics {
    static let shadowInset: CGFloat = 16
    static let compactHeight: CGFloat = 28
    static let compactGap: CGFloat = 12
    // Approx. 100×40 in Apple's iPhone 18 Pro product image; not a published hardware measurement.
    static let mockCameraAspect: CGFloat = 2.5
    static let mockCameraWidth = compactHeight * mockCameraAspect
    static let expandedRadius: CGFloat = 26
}

enum IslandGeometry {
    /// Center the small agent islands in the menu-bar band, not below it.
    static func topEdge(screen: CGRect, visible: CGRect, safeAreaTop: CGFloat) -> CGFloat {
        let menuHeight = max(30, safeAreaTop, screen.maxY - visible.maxY)
        return screen.maxY - max(0, (menuHeight - IslandMetrics.compactHeight) / 2)
    }
    static func surfaceFrame(screen: CGRect, visible: CGRect, safeAreaTop: CGFloat, size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2,
               y: topEdge(screen: screen, visible: visible, safeAreaTop: safeAreaTop) - size.height,
               width: size.width, height: size.height)
    }
    static func hostFrame(screen: CGRect, visible: CGRect, safeAreaTop: CGFloat, content: CGSize) -> CGRect {
        surfaceFrame(screen: screen, visible: visible, safeAreaTop: safeAreaTop, size: content)
            .insetBy(dx: -IslandMetrics.shadowInset, dy: -IslandMetrics.shadowInset)
    }
}
