import CoreGraphics

/// How monitor selection and the pointer interact on a multi-display Mac.
public struct MonitorBehavior: Codable, Equatable, Sendable {
    /// Switch the shown monitor when the pointer enters another one.
    /// Confirmed behavior: available, but OFF by default.
    public var followsCursor: Bool

    /// With `followsCursor` OFF and one monitor selected, keep the pointer on
    /// that monitor.
    ///
    /// The handoff left this undecided. Default ON: in trackpad mode the
    /// pointer is only useful while it is visible, and with auto-switch OFF a
    /// pointer that wanders onto the unshown monitor would act where the user
    /// cannot see. Turning it OFF lets the pointer leave; the view then stays
    /// on the selected monitor and shows where the pointer went.
    public var confinesCursorToSelectedMonitor: Bool

    public init(followsCursor: Bool = false, confinesCursorToSelectedMonitor: Bool = true) {
        self.followsCursor = followsCursor
        self.confinesCursorToSelectedMonitor = confinesCursorToSelectedMonitor
    }

    public static let `default` = MonitorBehavior()
}

/// Where the pointer is allowed to go.
public enum CursorBounds: Equatable, Sendable {
    /// Anywhere on any monitor.
    case anyMonitor
    /// Inside one rectangle (the selected monitor).
    case rect(CGRect)
}

extension MonitorLayout {
    public func cursorBounds(
        for selection: DisplaySelection,
        behavior: MonitorBehavior
    ) -> CursorBounds {
        switch resolve(selection) {
        case .all:
            return .anyMonitor
        case .monitor(let number):
            guard !behavior.followsCursor,
                  behavior.confinesCursorToSelectedMonitor,
                  let monitor = monitor(number: number) else { return .anyMonitor }
            return .rect(monitor.frame)
        }
    }

    public func clamp(_ point: CGPoint, to cursorBounds: CursorBounds) -> CGPoint {
        switch cursorBounds {
        case .anyMonitor:
            return clampToMonitors(point)
        case .rect(let rect):
            return rect.clampedPixelPoint(point)
        }
    }

    /// The selection after the pointer moved. Only an explicit single-monitor
    /// selection with auto-switch ON ever changes; "all" and auto-switch OFF
    /// keep the user's choice.
    public func selection(
        after cursor: CGPoint,
        current: DisplaySelection,
        behavior: MonitorBehavior
    ) -> DisplaySelection {
        guard behavior.followsCursor,
              case .monitor(let number) = resolve(current),
              let under = monitor(containing: cursor),
              under.id != number else { return current }
        return .monitor(under.id)
    }
}
