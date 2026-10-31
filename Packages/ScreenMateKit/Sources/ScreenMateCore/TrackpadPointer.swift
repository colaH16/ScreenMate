import CoreGraphics

public struct PointerSettings: Codable, Equatable, Sendable {
    /// Multiplier on finger travel. 1 moves the pointer as far on screen as
    /// the finger moved.
    public var sensitivity: CGFloat
    /// Extra gain for fast strokes, 0 disables acceleration.
    public var acceleration: CGFloat

    public init(sensitivity: CGFloat = 1.0, acceleration: CGFloat = 0.6) {
        self.sensitivity = sensitivity
        self.acceleration = acceleration
    }

    public static let `default` = PointerSettings()

    /// Speeds below this many points per second get no acceleration, so slow
    /// aiming stays exact.
    static let accelerationOnset: CGFloat = 200
    /// Speed span over which acceleration ramps to its maximum.
    static let accelerationRamp: CGFloat = 800
    static let accelerationCeiling: CGFloat = 1.5

    public func gain(forSpeed speed: CGFloat) -> CGFloat {
        let s = speed.isFinite ? max(0, speed) : 0
        let ramp = min(max(s - Self.accelerationOnset, 0) / Self.accelerationRamp, Self.accelerationCeiling)
        return sensitivity * (1 + max(0, acceleration) * ramp)
    }
}

/// Relative (trackpad-style) pointer.
///
/// Only finger deltas move the pointer. Where a finger lands is ignored, so
/// lifting and continuing elsewhere keeps moving from the current pointer
/// position, like a laptop trackpad. The pointer moves on screen by the
/// finger distance times the gain, so pinch-zooming in makes it more precise.
public struct TrackpadPointer: Equatable, Sendable {
    public private(set) var position: CGPoint
    public var settings: PointerSettings

    public init(position: CGPoint, settings: PointerSettings = .default) {
        self.position = position
        self.settings = settings
    }

    /// - Parameters:
    ///   - viewDelta: finger movement in view points since the last sample.
    ///   - speed: finger speed in points per second (for acceleration).
    ///   - scale: view points per framebuffer pixel.
    ///   - clamp: keeps the result on an allowed screen area.
    public mutating func move(
        byViewDelta viewDelta: CGPoint,
        speed: CGFloat,
        scale: CGFloat,
        clamp: (CGPoint) -> CGPoint
    ) {
        guard scale > 0, viewDelta.x.isFinite, viewDelta.y.isFinite else { return }
        let gain = settings.gain(forSpeed: speed)
        let next = CGPoint(
            x: position.x + viewDelta.x * gain / scale,
            y: position.y + viewDelta.y * gain / scale)
        position = clamp(next)
    }

    /// Move by framebuffer pixels without gain (external mouse deltas that
    /// the system has already accelerated).
    public mutating func move(byFramebufferDelta delta: CGPoint, clamp: (CGPoint) -> CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        position = clamp(CGPoint(x: position.x + delta.x, y: position.y + delta.y))
    }

    public mutating func warp(to point: CGPoint, clamp: (CGPoint) -> CGPoint) {
        position = clamp(point)
    }

    /// The whole pixel sent to the server.
    public var pixel: (x: UInt16, y: UInt16) {
        func convert(_ value: CGFloat) -> UInt16 {
            guard value.isFinite else { return 0 }
            return UInt16(clamping: Int(value.rounded(.down)))
        }
        return (convert(position.x), convert(position.y))
    }
}
