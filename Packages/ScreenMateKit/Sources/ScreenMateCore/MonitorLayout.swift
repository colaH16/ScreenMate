import CoreGraphics

/// One physical Mac display, in framebuffer pixel coordinates.
public struct RemoteMonitor: Equatable, Sendable, Identifiable {
    /// 1-based number in server order. The Mac announces its main display
    /// first, so monitor 1 is the main (menu-bar) display.
    public let id: Int
    public let frame: CGRect

    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// Where a monitor sits relative to monitor 1, for labels such as
/// "모니터 2 · 오른쪽".
public enum MonitorPlacement: Equatable, Sendable {
    case main
    case left
    case right
    case above
    case below
    case overlapping
}

/// Which part of the remote desktop the client shows.
public enum DisplaySelection: Hashable, Sendable, Codable {
    /// Every monitor at once (the combined desktop).
    case all
    /// One monitor, by its 1-based number.
    case monitor(Int)
}

/// The Mac's display arrangement mapped into the framebuffer the client
/// actually receives.
///
/// The server announces display rectangles in its own global space, where a
/// display left of or above the main one has negative coordinates, and
/// displays can differ in size and density. ScreenMate always receives the
/// combined desktop, so the framebuffer is the union of every display. This
/// type moves the union's origin to (0, 0) and, when the announced space and
/// the framebuffer use different units, scales each axis to match.
public struct MonitorLayout: Equatable, Sendable {
    public let monitors: [RemoteMonitor]
    /// `(0, 0, framebufferWidth, framebufferHeight)`.
    public let bounds: CGRect

    public static let empty = MonitorLayout(monitors: [], bounds: .zero)

    init(monitors: [RemoteMonitor], bounds: CGRect) {
        self.monitors = monitors
        self.bounds = bounds
    }

    public init(serverRegions: [CGRect], framebufferSize: CGSize) {
        guard framebufferSize.width >= 1, framebufferSize.height >= 1,
              framebufferSize.width.isFinite, framebufferSize.height.isFinite else {
            self = .empty
            return
        }
        let bounds = CGRect(origin: .zero, size: framebufferSize)
        let regions = serverRegions.filter {
            $0.width >= 1 && $0.height >= 1
                && $0.origin.x.isFinite && $0.origin.y.isFinite
                && $0.width.isFinite && $0.height.isFinite
        }
        guard let first = regions.first else {
            self.init(monitors: [RemoteMonitor(id: 1, frame: bounds)], bounds: bounds)
            return
        }

        let union = regions.dropFirst().reduce(first) { $0.union($1) }
        let tolerance: CGFloat = 1

        if abs(union.width - framebufferSize.width) <= tolerance,
           abs(union.height - framebufferSize.height) <= tolerance {
            // Combined desktop in the same units: translate only.
            let monitors = regions.enumerated().compactMap { index, region in
                Self.monitor(
                    id: index + 1,
                    frame: region.offsetBy(dx: -union.minX, dy: -union.minY),
                    bounds: bounds)
            }
            self.init(monitors: monitors, bounds: bounds)
            return
        }

        if let index = regions.firstIndex(where: {
            abs($0.width - framebufferSize.width) <= tolerance
                && abs($0.height - framebufferSize.height) <= tolerance
        }), regions.count > 1 {
            // The server encodes one display only (single-display mode).
            // Only that display exists in this framebuffer.
            self.init(
                monitors: [RemoteMonitor(id: index + 1, frame: bounds)],
                bounds: bounds)
            return
        }

        // Announced in different units than the framebuffer (for example
        // points versus Retina pixels): scale the arrangement per axis.
        let scaleX = framebufferSize.width / union.width
        let scaleY = framebufferSize.height / union.height
        let monitors = regions.enumerated().compactMap { index, region in
            Self.monitor(
                id: index + 1,
                frame: CGRect(
                    x: (region.minX - union.minX) * scaleX,
                    y: (region.minY - union.minY) * scaleY,
                    width: region.width * scaleX,
                    height: region.height * scaleY),
                bounds: bounds)
        }
        self.init(monitors: monitors, bounds: bounds)
    }

    private static func monitor(id: Int, frame: CGRect, bounds: CGRect) -> RemoteMonitor? {
        let rounded = CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded())
        let clipped = rounded.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return RemoteMonitor(id: id, frame: clipped)
    }

    public var isEmpty: Bool { monitors.isEmpty }
    public var hasMultipleMonitors: Bool { monitors.count > 1 }

    public func monitor(number: Int) -> RemoteMonitor? {
        monitors.first { $0.id == number }
    }

    public func monitor(containing point: CGPoint) -> RemoteMonitor? {
        monitors.first { $0.frame.containsPixel(point) }
    }

    public func nearestMonitor(to point: CGPoint) -> RemoteMonitor? {
        if let containing = monitor(containing: point) { return containing }
        return monitors.min {
            $0.frame.clampedPixelPoint(point).distance(to: point)
                < $1.frame.clampedPixelPoint(point).distance(to: point)
        }
    }

    /// The closest point that lies on some monitor. Gaps in the combined
    /// rectangle (displays of different heights) are not part of any screen,
    /// so the pointer must never rest there.
    public func clampToMonitors(_ point: CGPoint) -> CGPoint {
        guard let nearest = nearestMonitor(to: point) else {
            return bounds.isEmpty ? point : bounds.clampedPixelPoint(point)
        }
        return nearest.frame.clampedPixelPoint(point)
    }

    /// A selection that exists in this layout. A remembered monitor that is
    /// gone (display unplugged) falls back to monitor 1. Before the first
    /// layout arrives there is nothing to check against, so the remembered
    /// choice is kept.
    public func resolve(_ selection: DisplaySelection) -> DisplaySelection {
        guard !monitors.isEmpty else { return selection }
        switch selection {
        case .all:
            return .all
        case .monitor(let number):
            if monitor(number: number) != nil { return selection }
            if let first = monitors.first { return .monitor(first.id) }
            return .all
        }
    }

    /// The framebuffer rectangle shown for a selection.
    public func contentRect(for selection: DisplaySelection) -> CGRect {
        switch resolve(selection) {
        case .all:
            return bounds
        case .monitor(let number):
            return monitor(number: number)?.frame ?? bounds
        }
    }

    public func placement(of monitor: RemoteMonitor) -> MonitorPlacement {
        guard let main = monitors.first, main.id != monitor.id else { return .main }
        let a = monitor.frame
        let b = main.frame
        if a.maxX <= b.minX { return .left }
        if a.minX >= b.maxX { return .right }
        if a.maxY <= b.minY { return .above }
        if a.minY >= b.maxY { return .below }
        return .overlapping
    }
}
