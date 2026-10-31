import CoreGraphics

/// The part of the remote framebuffer currently on screen.
///
/// `viewSize` is the app-window area that actually shows the remote screen
/// (after toolbars, safe areas and the on-screen keyboard), never the device
/// size. `scale` is view points per framebuffer pixel.
public struct Viewport: Equatable, Sendable {
    public var origin: CGPoint
    public var scale: CGFloat
    public var viewSize: CGSize

    public init(origin: CGPoint, scale: CGFloat, viewSize: CGSize) {
        self.origin = origin
        self.scale = scale
        self.viewSize = viewSize
    }

    /// Framebuffer pixels visible along each axis.
    public var visibleSize: CGSize {
        guard scale > 0 else { return .zero }
        return CGSize(width: viewSize.width / scale, height: viewSize.height / scale)
    }

    public var visibleRect: CGRect { CGRect(origin: origin, size: visibleSize) }

    /// The center cell of the 3×3 grid laid over the visible area.
    public var deadZone: CGRect {
        let size = visibleSize
        return CGRect(
            x: origin.x + size.width * ViewportTracker.deadZoneLower,
            y: origin.y + size.height * ViewportTracker.deadZoneLower,
            width: size.width * (ViewportTracker.deadZoneUpper - ViewportTracker.deadZoneLower),
            height: size.height * (ViewportTracker.deadZoneUpper - ViewportTracker.deadZoneLower))
    }

    public func viewPoint(forFramebufferPoint point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) * scale, y: (point.y - origin.y) * scale)
    }

    public func framebufferPoint(forViewPoint point: CGPoint) -> CGPoint {
        guard scale > 0 else { return origin }
        return CGPoint(x: point.x / scale + origin.x, y: point.y / scale + origin.y)
    }

    public func viewRect(forFramebufferRect rect: CGRect) -> CGRect {
        CGRect(
            origin: viewPoint(forFramebufferPoint: rect.origin),
            size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }
}

/// Zoom as a multiple of "fit": 1 shows the whole selected content.
public struct ZoomPolicy: Equatable, Sendable {
    /// Upper bound on magnification, in view points per framebuffer pixel.
    public var maximumPointsPerPixel: CGFloat

    public init(maximumPointsPerPixel: CGFloat = 2) {
        self.maximumPointsPerPixel = maximumPointsPerPixel
    }

    public static func fitScale(content: CGSize, viewSize: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return 1 }
        return min(viewSize.width / content.width, viewSize.height / content.height)
    }

    public func maximumZoomFactor(content: CGSize, viewSize: CGSize) -> CGFloat {
        let fit = Self.fitScale(content: content, viewSize: viewSize)
        return max(1, maximumPointsPerPixel / fit)
    }

    public func clampedZoomFactor(_ factor: CGFloat, content: CGSize, viewSize: CGSize) -> CGFloat {
        guard factor.isFinite else { return 1 }
        return factor.clamped(1, maximumZoomFactor(content: content, viewSize: viewSize))
    }

    public func scale(forZoomFactor factor: CGFloat, content: CGSize, viewSize: CGSize) -> CGFloat {
        Self.fitScale(content: content, viewSize: viewSize)
            * clampedZoomFactor(factor, content: content, viewSize: viewSize)
    }
}

/// The confirmed central-third tracking rule.
///
/// The visible remote area is split 3×3. While the pointer stays in the
/// center cell the viewport does not move. When the pointer crosses the
/// center cell's edge, the viewport follows on that axis, in that direction,
/// in lockstep with the pointer, so the pointer stays on the center cell's
/// boundary instead of reaching the screen edge first. At the content edges
/// the viewport is clamped and the pointer may continue to the very edge.
/// An axis whose content already fits is centered and never pans.
public struct ViewportTracker: Equatable, Sendable {
    public static let deadZoneLower: CGFloat = 1.0 / 3.0
    public static let deadZoneUpper: CGFloat = 2.0 / 3.0

    public private(set) var viewport: Viewport
    public private(set) var content: CGRect

    /// Start with the pointer's cell centered as far as the content allows.
    public init(content: CGRect, viewSize: CGSize, scale: CGFloat, cursor: CGPoint) {
        self.content = content
        let visible = CGSize(
            width: scale > 0 ? viewSize.width / scale : 0,
            height: scale > 0 ? viewSize.height / scale : 0)
        let origin = CGPoint(
            x: Self.placeAxis(
                cursor: cursor.x, fraction: 0.5, visible: visible.width,
                contentMin: content.minX, contentLength: content.width),
            y: Self.placeAxis(
                cursor: cursor.y, fraction: 0.5, visible: visible.height,
                contentMin: content.minY, contentLength: content.height))
        viewport = Viewport(origin: origin, scale: scale, viewSize: viewSize)
    }

    /// Continuous pointer motion. Returns whether the viewport moved.
    @discardableResult
    public mutating func track(cursor: CGPoint) -> Bool {
        let visible = viewport.visibleSize
        let origin = CGPoint(
            x: Self.trackAxis(
                origin: viewport.origin.x, visible: visible.width,
                contentMin: content.minX, contentLength: content.width,
                cursor: cursor.x),
            y: Self.trackAxis(
                origin: viewport.origin.y, visible: visible.height,
                contentMin: content.minY, contentLength: content.height,
                cursor: cursor.y))
        let moved = origin != viewport.origin
        viewport.origin = origin
        return moved
    }

    /// The visible size changed (zoom, rotation, on-screen keyboard, iPad
    /// window resize) or the content changed (monitor switch). The pointer
    /// keeps its relative place on screen, pulled into the center cell, and
    /// the usual clamps apply.
    public mutating func relayout(
        content newContent: CGRect,
        viewSize: CGSize,
        scale: CGFloat,
        cursor: CGPoint
    ) {
        let oldVisible = viewport.visibleSize
        let oldOrigin = viewport.origin
        let contentChanged = newContent != content
        content = newContent
        let newVisible = CGSize(
            width: scale > 0 ? viewSize.width / scale : 0,
            height: scale > 0 ? viewSize.height / scale : 0)

        func fraction(_ cursor: CGFloat, _ origin: CGFloat, _ visible: CGFloat) -> CGFloat {
            // A content switch puts the pointer's cell back in the middle;
            // otherwise keep where the pointer sat on screen.
            guard !contentChanged, visible > 0 else { return 0.5 }
            return ((cursor - origin) / visible)
                .clamped(Self.deadZoneLower, Self.deadZoneUpper)
        }

        let origin = CGPoint(
            x: Self.placeAxis(
                cursor: cursor.x,
                fraction: fraction(cursor.x, oldOrigin.x, oldVisible.width),
                visible: newVisible.width,
                contentMin: newContent.minX, contentLength: newContent.width),
            y: Self.placeAxis(
                cursor: cursor.y,
                fraction: fraction(cursor.y, oldOrigin.y, oldVisible.height),
                visible: newVisible.height,
                contentMin: newContent.minY, contentLength: newContent.height))
        viewport = Viewport(origin: origin, scale: scale, viewSize: viewSize)
    }

    // MARK: - Per-axis rules

    /// Centered origin for an axis whose content fits entirely.
    static func centeredOrigin(visible: CGFloat, contentMin: CGFloat, contentLength: CGFloat) -> CGFloat {
        contentMin - (visible - contentLength) / 2
    }

    static func clampOrigin(_ origin: CGFloat, visible: CGFloat, contentMin: CGFloat, contentLength: CGFloat) -> CGFloat {
        origin.clamped(contentMin, contentMin + contentLength - visible)
    }

    static func trackAxis(
        origin: CGFloat,
        visible: CGFloat,
        contentMin: CGFloat,
        contentLength: CGFloat,
        cursor: CGFloat
    ) -> CGFloat {
        guard visible < contentLength else {
            return centeredOrigin(visible: visible, contentMin: contentMin, contentLength: contentLength)
        }
        var next = origin
        let lower = origin + visible * deadZoneLower
        let upper = origin + visible * deadZoneUpper
        if cursor < lower {
            next = cursor - visible * deadZoneLower
        } else if cursor > upper {
            next = cursor - visible * deadZoneUpper
        }
        return clampOrigin(next, visible: visible, contentMin: contentMin, contentLength: contentLength)
    }

    static func placeAxis(
        cursor: CGFloat,
        fraction: CGFloat,
        visible: CGFloat,
        contentMin: CGFloat,
        contentLength: CGFloat
    ) -> CGFloat {
        guard visible < contentLength else {
            return centeredOrigin(visible: visible, contentMin: contentMin, contentLength: contentLength)
        }
        return clampOrigin(
            cursor - visible * fraction,
            visible: visible, contentMin: contentMin, contentLength: contentLength)
    }
}
