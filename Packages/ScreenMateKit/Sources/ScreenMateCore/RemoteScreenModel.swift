import CoreGraphics

/// Everything about what part of the Mac is on screen and where the pointer
/// is, as one value. The session controller owns one and the view only
/// draws it, so every confirmed rule can be tested without a device.
public struct RemoteScreenModel: Equatable, Sendable {
    public private(set) var layout: MonitorLayout
    public private(set) var selection: DisplaySelection
    public private(set) var behavior: MonitorBehavior
    public private(set) var pointer: TrackpadPointer
    public private(set) var tracker: ViewportTracker
    /// Magnification relative to "fit" (1 shows the whole selection).
    public private(set) var zoomFactor: CGFloat
    public private(set) var viewSize: CGSize
    public let zoomPolicy: ZoomPolicy

    public struct MoveResult: Equatable, Sendable {
        public var viewportMoved: Bool
        public var selectionChanged: Bool
    }

    public init(
        layout: MonitorLayout,
        selection: DisplaySelection = .monitor(1),
        behavior: MonitorBehavior = .default,
        viewSize: CGSize,
        pointerSettings: PointerSettings = .default,
        zoomPolicy: ZoomPolicy = ZoomPolicy()
    ) {
        let resolved = layout.resolve(selection)
        let content = layout.contentRect(for: resolved)
        let start = layout.isEmpty
            ? CGPoint.zero
            : layout.clampToMonitors(CGPoint(x: content.midX, y: content.midY))
        let scale = zoomPolicy.scale(forZoomFactor: 1, content: content.size, viewSize: viewSize)
        self.layout = layout
        self.selection = resolved
        self.behavior = behavior
        self.pointer = TrackpadPointer(position: start, settings: pointerSettings)
        self.tracker = ViewportTracker(content: content, viewSize: viewSize, scale: scale, cursor: start)
        self.zoomFactor = 1
        self.viewSize = viewSize
        self.zoomPolicy = zoomPolicy
    }

    // MARK: - Derived

    public var viewport: Viewport { tracker.viewport }
    public var content: CGRect { layout.contentRect(for: selection) }
    public var cursorBounds: CursorBounds { layout.cursorBounds(for: selection, behavior: behavior) }
    public var scale: CGFloat {
        zoomPolicy.scale(forZoomFactor: zoomFactor, content: content.size, viewSize: viewSize)
    }

    /// False when the pointer sits on a monitor that is not shown (possible
    /// only with confinement turned off and auto-switch off).
    public var isPointerInContent: Bool { content.containsPixel(pointer.position) }

    /// The monitor the pointer is on, for the "pointer is on monitor 2" hint.
    public var pointerMonitor: RemoteMonitor? { layout.monitor(containing: pointer.position) }

    // MARK: - Pointer

    @discardableResult
    public mutating func movePointer(byViewDelta delta: CGPoint, speed: CGFloat) -> MoveResult {
        let bounds = cursorBounds
        let layout = self.layout
        pointer.move(byViewDelta: delta, speed: speed, scale: tracker.viewport.scale) {
            layout.clamp($0, to: bounds)
        }
        return afterPointerMove()
    }

    @discardableResult
    public mutating func movePointer(byFramebufferDelta delta: CGPoint) -> MoveResult {
        let bounds = cursorBounds
        let layout = self.layout
        pointer.move(byFramebufferDelta: delta) { layout.clamp($0, to: bounds) }
        return afterPointerMove()
    }

    private mutating func afterPointerMove() -> MoveResult {
        let next = layout.selection(after: pointer.position, current: selection, behavior: behavior)
        if next != selection {
            selection = next
            relayout()
            return MoveResult(viewportMoved: true, selectionChanged: true)
        }
        let moved = tracker.track(cursor: pointer.position)
        return MoveResult(viewportMoved: moved, selectionChanged: false)
    }

    // MARK: - Layout changes

    /// The Mac's framebuffer or display arrangement changed.
    public mutating func updateLayout(_ newLayout: MonitorLayout) {
        guard newLayout != layout else { return }
        let hadLayout = !layout.isEmpty
        layout = newLayout
        selection = newLayout.resolve(selection)
        let bounds = cursorBounds
        if hadLayout {
            pointer.warp(to: pointer.position) { newLayout.clamp($0, to: bounds) }
        } else {
            let content = self.content
            pointer.warp(to: CGPoint(x: content.midX, y: content.midY)) {
                newLayout.clamp($0, to: bounds)
            }
        }
        zoomFactor = zoomPolicy.clampedZoomFactor(zoomFactor, content: content.size, viewSize: viewSize)
        relayout()
    }

    /// Rotation, on-screen keyboard, toolbar or iPad window size change.
    public mutating func resize(viewSize newSize: CGSize) {
        guard newSize != viewSize else { return }
        viewSize = newSize
        zoomFactor = zoomPolicy.clampedZoomFactor(zoomFactor, content: content.size, viewSize: viewSize)
        relayout()
    }

    /// Pinch zoom, anchored on the pointer so the central-third rule still
    /// holds afterwards.
    public mutating func setZoomFactor(_ factor: CGFloat) {
        let clamped = zoomPolicy.clampedZoomFactor(factor, content: content.size, viewSize: viewSize)
        guard clamped != zoomFactor else { return }
        zoomFactor = clamped
        relayout()
    }

    /// Manual monitor choice. The pointer moves to the chosen monitor's
    /// center when it is not already there, so it is visible right away.
    public mutating func select(_ newSelection: DisplaySelection) {
        let resolved = layout.resolve(newSelection)
        guard resolved != selection else { return }
        selection = resolved
        let bounds = cursorBounds
        let layout = self.layout
        if case .monitor(let number) = resolved,
           let monitor = layout.monitor(number: number),
           !monitor.frame.containsPixel(pointer.position) {
            pointer.warp(to: CGPoint(x: monitor.frame.midX, y: monitor.frame.midY)) {
                layout.clamp($0, to: bounds)
            }
        } else {
            pointer.warp(to: pointer.position) { layout.clamp($0, to: bounds) }
        }
        zoomFactor = zoomPolicy.clampedZoomFactor(zoomFactor, content: content.size, viewSize: viewSize)
        relayout()
    }

    public mutating func setBehavior(_ newBehavior: MonitorBehavior) {
        behavior = newBehavior
        let bounds = cursorBounds
        let layout = self.layout
        pointer.warp(to: pointer.position) { layout.clamp($0, to: bounds) }
        tracker.track(cursor: pointer.position)
    }

    public mutating func setPointerSettings(_ settings: PointerSettings) {
        pointer.settings = settings
    }

    private mutating func relayout() {
        tracker.relayout(
            content: content,
            viewSize: viewSize,
            scale: scale,
            cursor: pointer.position)
    }
}
