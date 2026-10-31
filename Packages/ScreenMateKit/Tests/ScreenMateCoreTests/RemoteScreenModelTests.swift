import CoreGraphics
import Testing
@testable import ScreenMateCore

/// End-to-end rules on the combined model: what the user sees while moving,
/// zooming, rotating and switching monitors.
@Suite("Remote screen model")
struct RemoteScreenModelTests {
    // Main 2560×1080 with a 3440×1440 display to its right.
    let layout = MonitorLayout(
        serverRegions: [CGRect(x: 0, y: 0, width: 2560, height: 1080), CGRect(x: 2560, y: 0, width: 3440, height: 1440)],
        framebufferSize: CGSize(width: 6000, height: 1440))
    let phoneLandscape = CGSize(width: 844, height: 340)
    let phonePortrait = CGSize(width: 390, height: 700)
    let iPadLandscape = CGSize(width: 1180, height: 760)

    func model(_ view: CGSize, selection: DisplaySelection = .monitor(1), behavior: MonitorBehavior = .default) -> RemoteScreenModel {
        RemoteScreenModel(
            layout: layout, selection: selection, behavior: behavior, viewSize: view,
            pointerSettings: PointerSettings(acceleration: 0))
    }

    func assertPointerInCenterCellOrClamped(_ m: RemoteScreenModel, sourceLocation: SourceLocation = #_sourceLocation) {
        let vp = m.viewport
        let p = m.pointer.position
        let c = m.content
        let visible = vp.visibleSize
        let eps: CGFloat = 0.001
        if visible.width < c.width {
            let atMin = abs(vp.origin.x - c.minX) < eps
            let atMax = abs(vp.visibleRect.maxX - c.maxX) < eps
            if !(atMin && p.x < vp.deadZone.minX) && !(atMax && p.x > vp.deadZone.maxX) {
                #expect(p.x >= vp.deadZone.minX - eps && p.x <= vp.deadZone.maxX + eps, sourceLocation: sourceLocation)
            }
        }
        if visible.height < c.height {
            let atMin = abs(vp.origin.y - c.minY) < eps
            let atMax = abs(vp.visibleRect.maxY - c.maxY) < eps
            if !(atMin && p.y < vp.deadZone.minY) && !(atMax && p.y > vp.deadZone.maxY) {
                #expect(p.y >= vp.deadZone.minY - eps && p.y <= vp.deadZone.maxY + eps, sourceLocation: sourceLocation)
            }
        }
        #expect(vp.visibleRect.insetBy(dx: -eps, dy: -eps).contains(p) || !m.isPointerInContent, sourceLocation: sourceLocation)
    }

    @Test func startsAtFitWithPointerCenteredOnSelectedMonitor() {
        for view in [phoneLandscape, phonePortrait, iPadLandscape] {
            let m = model(view)
            #expect(m.zoomFactor == 1)
            #expect(m.content == CGRect(x: 0, y: 0, width: 2560, height: 1080))
            #expect(m.pointer.position == CGPoint(x: 1280, y: 540))
            // At fit the whole monitor is visible: nothing pans.
            #expect(m.viewport.visibleRect.contains(m.content))
        }
    }

    @Test func zoomedInPointerSweepAlwaysStaysInCenterCellOrAtClampedEdge() {
        for view in [phoneLandscape, phonePortrait, iPadLandscape] {
            var m = model(view)
            m.setZoomFactor(3)
            assertPointerInCenterCellOrClamped(m)
            let moves: [CGPoint] = Array(repeating: CGPoint(x: 9, y: 0), count: 200)
                + Array(repeating: CGPoint(x: 0, y: 7), count: 120)
                + Array(repeating: CGPoint(x: -11, y: -4), count: 300)
            for d in moves {
                m.movePointer(byViewDelta: d, speed: 100)
                assertPointerInCenterCellOrClamped(m)
            }
        }
    }

    @Test func pinchRecomputesAndKeepsRule() {
        var m = model(iPadLandscape)
        m.setZoomFactor(2)
        for _ in 0..<40 { m.movePointer(byViewDelta: CGPoint(x: 12, y: 5), speed: 100) }
        for factor: CGFloat in [2.5, 4, 1.6, 6, 1] {
            m.setZoomFactor(factor)
            assertPointerInCenterCellOrClamped(m)
        }
        #expect(m.zoomFactor == 1)
        #expect(m.viewport.visibleRect.contains(m.content))
    }

    @Test func zoomFactorIsClampedToFitAndMaximum() {
        var m = model(phoneLandscape)
        m.setZoomFactor(0.1)
        #expect(m.zoomFactor == 1)
        m.setZoomFactor(10_000)
        #expect(abs(m.scale - m.zoomPolicy.maximumPointsPerPixel) < 0.0001)
    }

    @Test func rotationAndKeyboardAndWindowResizeRecompute() {
        var m = model(phoneLandscape)
        m.setZoomFactor(2.5)
        for _ in 0..<30 { m.movePointer(byViewDelta: CGPoint(x: 15, y: 6), speed: 100) }
        let pointer = m.pointer.position
        for size in [phonePortrait, CGSize(width: 390, height: 360), phoneLandscape, CGSize(width: 507, height: 700), iPadLandscape] {
            m.resize(viewSize: size)
            #expect(m.viewport.viewSize == size)
            #expect(m.pointer.position == pointer)
            assertPointerInCenterCellOrClamped(m)
        }
    }

    @Test func confinedPointerCannotLeaveSelectedMonitor() {
        var m = model(iPadLandscape)
        for _ in 0..<500 { m.movePointer(byViewDelta: CGPoint(x: 50, y: 0), speed: 100) }
        #expect(m.pointer.position.x == 2559)
        #expect(m.selection == .monitor(1))
        #expect(m.isPointerInContent)
    }

    @Test func autoSwitchOffWithoutConfinementKeepsSelectedMonitorShown() {
        var m = model(iPadLandscape, behavior: MonitorBehavior(followsCursor: false, confinesCursorToSelectedMonitor: false))
        let origin = m.viewport.origin
        for _ in 0..<500 { m.movePointer(byViewDelta: CGPoint(x: 50, y: 0), speed: 100) }
        #expect(m.selection == .monitor(1))
        #expect(m.pointerMonitor?.id == 2)
        #expect(!m.isPointerInContent)
        #expect(m.viewport.origin == origin)
    }

    @Test func autoSwitchOnFollowsPointerToOtherMonitor() {
        var m = model(iPadLandscape, behavior: MonitorBehavior(followsCursor: true))
        var switched = false
        for _ in 0..<500 {
            if m.movePointer(byViewDelta: CGPoint(x: 50, y: 0), speed: 100).selectionChanged { switched = true }
        }
        #expect(switched)
        #expect(m.selection == .monitor(2))
        #expect(m.content == CGRect(x: 2560, y: 0, width: 3440, height: 1440))
        #expect(m.isPointerInContent)
    }

    @Test func manualSelectionMovesPointerOntoChosenMonitorAndKeepsZoom() {
        var m = model(phoneLandscape)
        m.setZoomFactor(2)
        m.select(.monitor(2))
        #expect(m.selection == .monitor(2))
        #expect(m.pointer.position == CGPoint(x: 2560 + 1720, y: 720))
        #expect(m.zoomFactor == 2)
        assertPointerInCenterCellOrClamped(m)
        m.select(.all)
        #expect(m.content == layout.bounds)
        #expect(m.pointer.position == CGPoint(x: 4280, y: 720))
    }

    @Test func allMonitorsViewNeverRestsPointerInGap() {
        var m = model(iPadLandscape, selection: .all)
        // Down-left into the area under the shorter main display.
        for _ in 0..<300 { m.movePointer(byViewDelta: CGPoint(x: -20, y: 20), speed: 100) }
        #expect(layout.monitor(containing: m.pointer.position) != nil)
    }

    @Test func layoutChangeKeepsPointerAndFallsBackWhenMonitorDisappears() {
        var m = model(iPadLandscape, selection: .monitor(2))
        let single = MonitorLayout(serverRegions: [], framebufferSize: CGSize(width: 2560, height: 1080))
        m.updateLayout(single)
        #expect(m.selection == .monitor(1))
        #expect(single.monitor(containing: m.pointer.position) != nil)
    }

    @Test func emptyLayoutAdoptsFirstRealLayoutCentered() {
        var m = RemoteScreenModel(layout: .empty, viewSize: phoneLandscape)
        m.updateLayout(layout)
        #expect(m.pointer.position == CGPoint(x: 1280, y: 540))
        #expect(m.selection == .monitor(1))
    }
}
