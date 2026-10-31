import CoreGraphics
import Testing
@testable import ScreenMateCore

/// Confirmed behavior 6: dual monitors, negative coordinates, mixed sizes.
@Suite("Monitor layout")
struct MonitorLayoutTests {
    @Test func noRegionsMeansOneMonitorCoveringFramebuffer() {
        let layout = MonitorLayout(serverRegions: [], framebufferSize: CGSize(width: 1920, height: 1080))
        #expect(layout.monitors == [RemoteMonitor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))])
        #expect(!layout.hasMultipleMonitors)
    }

    @Test func emptyFramebufferIsEmptyLayout() {
        #expect(MonitorLayout(serverRegions: [CGRect(x: 0, y: 0, width: 10, height: 10)], framebufferSize: .zero).isEmpty)
    }

    @Test func sideBySideMixedSizesKeepServerOrder() {
        // This Mac mini: main 2560×1080 (points of a 5K2K panel) and a
        // 3440×1440 display to its right, top-aligned.
        let regions = [
            CGRect(x: 0, y: 0, width: 2560, height: 1080),
            CGRect(x: 2560, y: 0, width: 3440, height: 1440),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 6000, height: 1440))
        #expect(layout.monitors.map(\.id) == [1, 2])
        #expect(layout.monitors[0].frame == regions[0])
        #expect(layout.monitors[1].frame == regions[1])
        #expect(layout.placement(of: layout.monitors[0]) == .main)
        #expect(layout.placement(of: layout.monitors[1]) == .right)
    }

    @Test func negativeOriginsAreTranslatedIntoFramebufferSpace() {
        // Secondary display left of and above the main one.
        let regions = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: -2560, y: -360, width: 2560, height: 1440),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 4480, height: 1440))
        #expect(layout.monitors[0].frame == CGRect(x: 2560, y: 360, width: 1920, height: 1080))
        #expect(layout.monitors[1].frame == CGRect(x: 0, y: 0, width: 2560, height: 1440))
        #expect(layout.placement(of: layout.monitors[1]) == .left)
    }

    @Test func verticalArrangementWithNegativeY() {
        let regions = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -200, y: -1440, width: 3440, height: 1440),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 3440, height: 2422))
        #expect(layout.monitors[1].frame == CGRect(x: 0, y: 0, width: 3440, height: 1440))
        #expect(layout.monitors[0].frame == CGRect(x: 200, y: 1440, width: 1512, height: 982))
        #expect(layout.placement(of: layout.monitors[1]) == .above)
    }

    @Test func differentUnitsAreScaledPerAxis() {
        // Arrangement announced in points, framebuffer delivered at 2×.
        let regions = [
            CGRect(x: 0, y: 0, width: 1280, height: 540),
            CGRect(x: 1280, y: 0, width: 1720, height: 720),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 6000, height: 1440))
        #expect(layout.monitors[0].frame == CGRect(x: 0, y: 0, width: 2560, height: 1080))
        #expect(layout.monitors[1].frame == CGRect(x: 2560, y: 0, width: 3440, height: 1440))
    }

    @Test func singleDisplayFramebufferKeepsOnlyThatDisplay() {
        let regions = [
            CGRect(x: 0, y: 0, width: 2560, height: 1080),
            CGRect(x: 2560, y: 0, width: 3440, height: 1440),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 3440, height: 1440))
        #expect(layout.monitors == [RemoteMonitor(id: 2, frame: CGRect(x: 0, y: 0, width: 3440, height: 1440))])
    }

    @Test func invalidRegionsAreIgnored() {
        let regions = [
            CGRect(x: 0, y: 0, width: 0, height: 1080),
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let layout = MonitorLayout(serverRegions: regions, framebufferSize: CGSize(width: 1920, height: 1080))
        #expect(layout.monitors.count == 1)
        #expect(layout.monitors[0].frame.size == CGSize(width: 1920, height: 1080))
    }

    @Test func pointerNeverRestsInTheGapBetweenDifferentHeights() {
        let layout = MonitorLayout(
            serverRegions: [CGRect(x: 0, y: 0, width: 2560, height: 1080), CGRect(x: 2560, y: 0, width: 3440, height: 1440)],
            framebufferSize: CGSize(width: 6000, height: 1440))
        // Below the shorter main display: not on any screen.
        let gap = CGPoint(x: 1000, y: 1300)
        #expect(layout.monitor(containing: gap) == nil)
        let clamped = layout.clampToMonitors(gap)
        #expect(clamped == CGPoint(x: 1000, y: 1079))
        #expect(layout.monitor(containing: clamped)?.id == 1)
        // Far right edge.
        #expect(layout.clampToMonitors(CGPoint(x: 9000, y: 9000)) == CGPoint(x: 5999, y: 1439))
    }

    @Test func missingMonitorSelectionFallsBackToMonitorOne() {
        let layout = MonitorLayout(serverRegions: [], framebufferSize: CGSize(width: 1920, height: 1080))
        #expect(layout.resolve(.monitor(2)) == .monitor(1))
        #expect(layout.resolve(.all) == .all)
        #expect(layout.contentRect(for: .monitor(2)) == layout.bounds)
    }
}

@Suite("Monitor selection and pointer confinement")
struct MonitorBehaviorTests {
    let layout = MonitorLayout(
        serverRegions: [CGRect(x: 0, y: 0, width: 2560, height: 1080), CGRect(x: 2560, y: 0, width: 3440, height: 1440)],
        framebufferSize: CGSize(width: 6000, height: 1440))

    @Test func autoSwitchIsOffByDefaultAndConfinementOn() {
        let behavior = MonitorBehavior()
        #expect(behavior.followsCursor == false)
        #expect(behavior.confinesCursorToSelectedMonitor == true)
    }

    @Test func autoSwitchOffKeepsSelection() {
        let next = layout.selection(after: CGPoint(x: 4000, y: 500), current: .monitor(1), behavior: MonitorBehavior())
        #expect(next == .monitor(1))
    }

    @Test func autoSwitchOnFollowsPointer() {
        let on = MonitorBehavior(followsCursor: true)
        #expect(layout.selection(after: CGPoint(x: 4000, y: 500), current: .monitor(1), behavior: on) == .monitor(2))
        #expect(layout.selection(after: CGPoint(x: 100, y: 500), current: .monitor(2), behavior: on) == .monitor(1))
        // "All" is never replaced.
        #expect(layout.selection(after: CGPoint(x: 4000, y: 500), current: .all, behavior: on) == .all)
    }

    @Test func confinedPointerStopsAtSelectedMonitorEdge() {
        let bounds = layout.cursorBounds(for: .monitor(1), behavior: MonitorBehavior())
        #expect(bounds == .rect(CGRect(x: 0, y: 0, width: 2560, height: 1080)))
        #expect(layout.clamp(CGPoint(x: 3000, y: 2000), to: bounds) == CGPoint(x: 2559, y: 1079))
    }

    @Test func unconfinedOrFollowingPointerMayCrossMonitors() {
        let free = layout.cursorBounds(for: .monitor(1), behavior: MonitorBehavior(confinesCursorToSelectedMonitor: false))
        #expect(free == .anyMonitor)
        let following = layout.cursorBounds(for: .monitor(1), behavior: MonitorBehavior(followsCursor: true))
        #expect(following == .anyMonitor)
        #expect(layout.cursorBounds(for: .all, behavior: MonitorBehavior()) == .anyMonitor)
        #expect(layout.clamp(CGPoint(x: 3000, y: 1300), to: free) == CGPoint(x: 3000, y: 1300))
    }
}
