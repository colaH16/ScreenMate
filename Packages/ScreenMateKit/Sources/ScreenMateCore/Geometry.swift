import CoreGraphics

extension CGFloat {
    /// Clamp into `lower...upper`. When the range is inverted (an empty
    /// rectangle), the lower bound wins so callers never get NaN.
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        if upper < lower { return lower }
        return Swift.min(Swift.max(self, lower), upper)
    }
}

extension CGRect {
    /// Largest coordinate a pixel-addressed pointer may occupy along each
    /// axis. Remote pointer events address whole pixels, so the last valid
    /// column is `maxX - 1`, not `maxX`.
    var lastPixelX: CGFloat { Swift.max(minX, maxX - 1) }
    var lastPixelY: CGFloat { Swift.max(minY, maxY - 1) }

    /// The point inside this rectangle's pixel grid closest to `point`.
    public func clampedPixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x.clamped(minX, lastPixelX),
            y: point.y.clamped(minY, lastPixelY))
    }

    /// Whether `point` lies on one of this rectangle's pixels
    /// (half-open on the max edges).
    public func containsPixel(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    var length: CGFloat { (x * x + y * y).squareRoot() }
}
