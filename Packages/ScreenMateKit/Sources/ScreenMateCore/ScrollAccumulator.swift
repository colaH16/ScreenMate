import CoreGraphics

/// One remote scroll sample: precise point deltas for Apple's continuous
/// (trackpad) scroll event plus whole wheel units for line-based fallbacks.
public struct ScrollSample: Equatable, Sendable {
    public var pointDeltaX: Int32
    public var pointDeltaY: Int32
    public var wheelDeltaX: Int16
    public var wheelDeltaY: Int16

    public init(pointDeltaX: Int32, pointDeltaY: Int32, wheelDeltaX: Int16, wheelDeltaY: Int16) {
        self.pointDeltaX = pointDeltaX
        self.pointDeltaY = pointDeltaY
        self.wheelDeltaX = wheelDeltaX
        self.wheelDeltaY = wheelDeltaY
    }

    public var isZero: Bool {
        pointDeltaX == 0 && pointDeltaY == 0 && wheelDeltaX == 0 && wheelDeltaY == 0
    }

    /// 16.16 fixed-point wheel units, the "fixed" fields of a CGEvent scroll.
    public var fixedDeltaX: Int32 { Self.fixed16_16(pointDeltaX) }
    public var fixedDeltaY: Int32 { Self.fixed16_16(pointDeltaY) }

    static func fixed16_16(_ points: Int32) -> Int32 {
        Int32(clamping: Int64(points) * 65_536 / ScrollAccumulator.pointsPerWheelUnit)
    }
}

/// Turns two-finger drag deltas into remote scroll samples on both axes at
/// once (vertical, horizontal and diagonal), without losing fractions.
///
/// The sign follows the finger, as with macOS natural scrolling: fingers
/// moving down send positive Y and the page moves down with them. The
/// session marks the events "direction inverted from device" accordingly.
public struct ScrollAccumulator: Equatable, Sendable {
    /// Points of motion per whole wheel unit, matching public trackpad
    /// CGEvents.
    public static let pointsPerWheelUnit: Int64 = 10

    private var fractionX: CGFloat = 0
    private var fractionY: CGFloat = 0
    private var wheelRemainderX: Int64 = 0
    private var wheelRemainderY: Int64 = 0

    public init() {}

    /// Gain applied to finger travel. Zoomed out, one view point covers
    /// several remote pixels; scaling by `1 / scale` (bounded) keeps remote
    /// content moving with the fingers instead of crawling.
    public static func gain(scale: CGFloat, sensitivity: CGFloat = 1) -> CGFloat {
        guard scale > 0, scale.isFinite else { return sensitivity }
        return sensitivity * (1 / scale).clamped(1, 4)
    }

    public mutating func consume(viewDelta: CGPoint, gain: CGFloat) -> ScrollSample {
        guard viewDelta.x.isFinite, viewDelta.y.isFinite, gain.isFinite else {
            return ScrollSample(pointDeltaX: 0, pointDeltaY: 0, wheelDeltaX: 0, wheelDeltaY: 0)
        }
        let totalX = fractionX + viewDelta.x * gain
        let totalY = fractionY + viewDelta.y * gain
        let pointX = totalX.rounded(.towardZero)
        let pointY = totalY.rounded(.towardZero)
        fractionX = totalX - pointX
        fractionY = totalY - pointY

        let px = Int32(clamping: Int64(pointX))
        let py = Int32(clamping: Int64(pointY))
        wheelRemainderX += Int64(px)
        wheelRemainderY += Int64(py)
        let wheelX = wheelRemainderX / Self.pointsPerWheelUnit
        let wheelY = wheelRemainderY / Self.pointsPerWheelUnit
        wheelRemainderX -= wheelX * Self.pointsPerWheelUnit
        wheelRemainderY -= wheelY * Self.pointsPerWheelUnit

        return ScrollSample(
            pointDeltaX: px,
            pointDeltaY: py,
            wheelDeltaX: Int16(clamping: wheelX),
            wheelDeltaY: Int16(clamping: wheelY))
    }

    public mutating func reset() {
        self = ScrollAccumulator()
    }
}
