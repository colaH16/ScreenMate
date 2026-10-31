import CoreGraphics
import Foundation

/// Mouse actions produced by one-finger touch gestures.
public enum PointerAction: Equatable, Sendable {
    /// Left button down and up at the pointer.
    case click
    /// Left button held down (start of a drag).
    case pressDown
    /// Left button released (end of a drag).
    case release
}

/// One-finger tap and drag rules.
///
/// - A tap is a left click.
/// - Two taps in a row are a double-click.
/// - Tap, then touch again within `window` and move: drag (tap-and-a-half,
///   as with macOS "drag with double-tap"). The first tap's click is
///   swallowed so the drag starts as a single press; a delayed click would
///   otherwise make the Mac see a double-click (zoom a title bar, open a
///   file) instead of a drag.
///
/// The cost is that a lone tap is reported `window` seconds after the
/// finger lifts. Plain one-finger movement without a preceding tap only
/// moves the pointer.
public struct TapDragArbiter: Equatable, Sendable {
    public static let defaultWindow: TimeInterval = 0.25

    public let window: TimeInterval
    /// Time of a tap whose click is being held back.
    public private(set) var pendingTapTime: TimeInterval?
    /// A new touch landed while a tap was pending.
    public private(set) var secondTouchArmed = false
    public private(set) var isDragging = false

    public init(window: TimeInterval = TapDragArbiter.defaultWindow) {
        self.window = window
    }

    /// When a scheduled `deadline` call should run, if any.
    public var nextDeadline: TimeInterval? {
        guard let pendingTapTime, !secondTouchArmed else { return nil }
        return pendingTapTime + window
    }

    public mutating func touchDown(at time: TimeInterval) {
        if let pendingTapTime, time - pendingTapTime <= window {
            secondTouchArmed = true
        }
    }

    public mutating func tap(at time: TimeInterval) -> [PointerAction] {
        if pendingTapTime != nil, secondTouchArmed {
            reset()
            return [.click, .click]
        }
        var actions: [PointerAction] = []
        if pendingTapTime != nil {
            // A stale pending tap that the deadline has not flushed yet.
            actions.append(.click)
        }
        pendingTapTime = time
        secondTouchArmed = false
        return actions
    }

    /// Timer callback; flushes a lone tap once its window has passed.
    public mutating func deadline(at time: TimeInterval) -> [PointerAction] {
        guard let pendingTapTime, !secondTouchArmed,
              time - pendingTapTime >= window - 0.0001 else { return [] }
        self.pendingTapTime = nil
        return [.click]
    }

    public mutating func panBegan(at time: TimeInterval) -> [PointerAction] {
        if pendingTapTime != nil, secondTouchArmed {
            pendingTapTime = nil
            secondTouchArmed = false
            isDragging = true
            return [.pressDown]
        }
        if pendingTapTime != nil {
            pendingTapTime = nil
            return [.click]
        }
        return []
    }

    public mutating func panEnded() -> [PointerAction] {
        guard isDragging else { return [] }
        isDragging = false
        return [.release]
    }

    /// Every finger lifted. A second touch that neither tapped nor dragged
    /// (held still, then lifted) releases the held-back click.
    public mutating func allTouchesLifted(at time: TimeInterval) -> [PointerAction] {
        if isDragging {
            isDragging = false
            return [.release]
        }
        guard pendingTapTime != nil, secondTouchArmed else { return [] }
        reset()
        return [.click]
    }

    /// Another gesture (scroll, zoom, right-click) took over. A held-back tap
    /// is still a click and goes out first.
    public mutating func flush() -> [PointerAction] {
        var actions: [PointerAction] = []
        if isDragging { actions.append(.release) }
        if pendingTapTime != nil { actions.append(.click) }
        reset()
        return actions
    }

    private mutating func reset() {
        pendingTapTime = nil
        secondTouchArmed = false
        isDragging = false
    }
}

/// Decides once per two-finger gesture whether it is a scroll or a pinch,
/// then stays with that answer, so a scroll does not zoom and a zoom does
/// not scroll.
public struct TwoFingerClassifier: Equatable, Sendable {
    public enum Intent: Equatable, Sendable {
        case undecided
        case scroll
        case zoom
    }

    /// Travel in points before deciding.
    public static let decisionDistance: CGFloat = 10

    public let initialSpan: CGFloat
    public private(set) var intent: Intent = .undecided

    public init(initialSpan: CGFloat) {
        self.initialSpan = initialSpan
    }

    /// - Parameters:
    ///   - translation: centroid movement since the gesture began.
    ///   - span: current distance between the two fingers.
    @discardableResult
    public mutating func update(translation: CGPoint, span: CGFloat) -> Intent {
        guard intent == .undecided else { return intent }
        let move = translation.length
        let spanChange = abs(span - initialSpan)
        guard move >= Self.decisionDistance || spanChange >= Self.decisionDistance else {
            return intent
        }
        intent = spanChange > move ? .zoom : .scroll
        return intent
    }

    /// Zoom multiplier relative to the start of the gesture.
    public func zoomRatio(span: CGFloat) -> CGFloat {
        guard initialSpan > 0, span > 0 else { return 1 }
        return span / initialSpan
    }
}
