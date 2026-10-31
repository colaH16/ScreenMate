import CoreGraphics
import Testing
@testable import ScreenMateCore

/// Confirmed behavior 3: central-third dead zone over the visible remote area.
@Suite("Viewport central-third tracking")
struct ViewportTrackerTests {
    // 3440×1440 monitor shown 1:1 in a 1000×600 pt area.
    let monitor = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    let view = CGSize(width: 1000, height: 600)

    func tracker(cursor: CGPoint, scale: CGFloat = 1) -> ViewportTracker {
        ViewportTracker(content: monitor, viewSize: view, scale: scale, cursor: cursor)
    }

    @Test func viewportStaysStillInsideCenterCell() {
        var t = tracker(cursor: CGPoint(x: 1720, y: 720))
        let start = t.viewport.origin
        let zone = t.viewport.deadZone
        // Anywhere inside the center cell, including its edges.
        for p in [CGPoint(x: zone.minX, y: zone.minY), CGPoint(x: zone.maxX, y: zone.maxY),
                  CGPoint(x: zone.midX + 50, y: zone.midY - 40)] {
            do { let r = t.track(cursor: p); #expect(r == false) }
            #expect(t.viewport.origin == start)
        }
    }

    @Test func followsAsSoonAsPointerLeavesCenterCellNotAtScreenEdge() {
        var t = tracker(cursor: CGPoint(x: 1720, y: 720))
        let zone = t.viewport.deadZone
        // One pixel past the right third boundary: the view must already move,
        // long before the pointer reaches the visible edge.
        let p = CGPoint(x: zone.maxX + 1, y: zone.midY)
        do { let r = t.track(cursor: p); #expect(r) }
        #expect(t.viewport.deadZone.maxX == p.x)
        #expect(t.viewport.visibleRect.maxX > p.x + 300)
    }

    @Test func pointerIsHeldOnCenterCellBoundaryWhileMoving() {
        var t = tracker(cursor: CGPoint(x: 1720, y: 720))
        var x: CGFloat = 1720
        for _ in 0..<80 {
            x += 7
            t.track(cursor: CGPoint(x: x, y: 720))
            let zone = t.viewport.deadZone
            let maxOrigin = monitor.maxX - t.viewport.visibleSize.width
            if t.viewport.origin.x < maxOrigin {
                #expect(x <= zone.maxX + 0.0001)
            }
            #expect(x >= zone.minX - 0.0001)
        }
    }

    @Test func followsEachAxisAndDirectionIndependently() {
        var t = tracker(cursor: CGPoint(x: 1720, y: 720))
        let o = t.viewport.origin
        // Down only.
        t.track(cursor: CGPoint(x: 1720, y: t.viewport.deadZone.maxY + 20))
        #expect(t.viewport.origin.x == o.x)
        #expect(t.viewport.origin.y == o.y + 20)
        // Left only.
        let o2 = t.viewport.origin
        t.track(cursor: CGPoint(x: t.viewport.deadZone.minX - 30, y: t.viewport.deadZone.midY))
        #expect(t.viewport.origin.x == o2.x - 30)
        #expect(t.viewport.origin.y == o2.y)
        // Up-right diagonal.
        let o3 = t.viewport.origin
        let zone = t.viewport.deadZone
        t.track(cursor: CGPoint(x: zone.maxX + 10, y: zone.minY - 15))
        #expect(t.viewport.origin.x == o3.x + 10)
        #expect(t.viewport.origin.y == o3.y - 15)
    }

    @Test func clampsAtMonitorEdgeAndPointerReachesTheEdge() {
        var t = tracker(cursor: CGPoint(x: 1720, y: 720))
        let lastPixel = CGPoint(x: monitor.maxX - 1, y: monitor.maxY - 1)
        t.track(cursor: lastPixel)
        #expect(t.viewport.visibleRect.maxX == monitor.maxX)
        #expect(t.viewport.visibleRect.maxY == monitor.maxY)
        #expect(t.viewport.visibleRect.contains(lastPixel))
        t.track(cursor: CGPoint(x: 0, y: 0))
        #expect(t.viewport.origin == .zero)
    }

    @Test func axisThatAlreadyFitsIsCenteredAndNeverPans() {
        // At 0.3 pt/px the visible area is 3333×2000 px: the 1440 px height
        // fits, the 3440 px width does not.
        var t = tracker(cursor: CGPoint(x: 1720, y: 720), scale: 0.3)
        let visible = t.viewport.visibleSize
        #expect(visible.height >= monitor.height)
        let centeredY = monitor.minY - (visible.height - monitor.height) / 2
        #expect(t.viewport.origin.y == centeredY)
        t.track(cursor: CGPoint(x: 1720, y: 1439))
        #expect(t.viewport.origin.y == centeredY)
        t.track(cursor: CGPoint(x: 1720, y: 0))
        #expect(t.viewport.origin.y == centeredY)
        // The other axis still tracks.
        t.track(cursor: CGPoint(x: 3439, y: 720))
        #expect(t.viewport.visibleRect.maxX == monitor.maxX)
    }

    @Test func fullyFittingContentNeverPans() {
        var t = tracker(cursor: CGPoint(x: 100, y: 100), scale: 0.2)
        let origin = t.viewport.origin
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 3439, y: 1439), CGPoint(x: 3000, y: 10)] {
            do { let r = t.track(cursor: p); #expect(r == false) }
            #expect(t.viewport.origin == origin)
        }
    }

    @Test func nonZeroContentOriginIsRespected() {
        // Second monitor to the right of a 2560-wide main display.
        let second = CGRect(x: 2560, y: 0, width: 3440, height: 1440)
        var t = ViewportTracker(content: second, viewSize: view, scale: 1, cursor: CGPoint(x: 4280, y: 720))
        t.track(cursor: CGPoint(x: 2560, y: 0))
        #expect(t.viewport.origin == CGPoint(x: 2560, y: 0))
        t.track(cursor: CGPoint(x: second.maxX - 1, y: second.maxY - 1))
        #expect(t.viewport.visibleRect.maxX == second.maxX)
        #expect(t.viewport.visibleRect.maxY == second.maxY)
    }
}

/// Zoom, rotation, keyboard and window changes re-run the same rule.
@Suite("Viewport relayout")
struct ViewportRelayoutTests {
    let monitor = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    @Test func zoomKeepsPointerInsideCenterCell() {
        var t = ViewportTracker(content: monitor, viewSize: CGSize(width: 1000, height: 600), scale: 1, cursor: CGPoint(x: 1500, y: 700))
        let cursor = CGPoint(x: 1500, y: 700)
        for scale: CGFloat in [1.5, 2, 0.6, 0.45] {
            t.relayout(content: monitor, viewSize: CGSize(width: 1000, height: 600), scale: scale, cursor: cursor)
            let vp = t.viewport
            #expect(vp.scale == scale)
            let visible = vp.visibleSize
            if visible.width < monitor.width {
                #expect(vp.deadZone.minX - 0.0001 <= cursor.x && cursor.x <= vp.deadZone.maxX + 0.0001)
            }
            if visible.height < monitor.height {
                #expect(vp.deadZone.minY - 0.0001 <= cursor.y && cursor.y <= vp.deadZone.maxY + 0.0001)
            }
        }
    }

    @Test func zoomKeepsPointerAtSameRelativePlaceWhenInsideCenterCell() {
        var t = ViewportTracker(content: monitor, viewSize: CGSize(width: 1000, height: 600), scale: 1, cursor: CGPoint(x: 1720, y: 720))
        let cursor = CGPoint(x: 1720 + 100, y: 720)
        t.track(cursor: cursor)
        let before = t.viewport.viewPoint(forFramebufferPoint: cursor)
        t.relayout(content: monitor, viewSize: CGSize(width: 1000, height: 600), scale: 1.25, cursor: cursor)
        let after = t.viewport.viewPoint(forFramebufferPoint: cursor)
        #expect(abs(before.x - after.x) < 0.001)
        #expect(abs(before.y - after.y) < 0.001)
    }

    @Test func rotationSwapsAxesAndReappliesRule() {
        let cursor = CGPoint(x: 3000, y: 1300)
        var t = ViewportTracker(content: monitor, viewSize: CGSize(width: 844, height: 390), scale: 0.5, cursor: cursor)
        // Portrait.
        t.relayout(content: monitor, viewSize: CGSize(width: 390, height: 844), scale: 0.5, cursor: cursor)
        let vp = t.viewport
        #expect(vp.viewSize == CGSize(width: 390, height: 844))
        #expect(vp.visibleRect.contains(cursor))
        // 844/0.5 = 1688 px ≥ 1440: vertical axis now fits and is centered.
        #expect(vp.origin.y == monitor.minY - (vp.visibleSize.height - monitor.height) / 2)
        // Horizontal is clamped to the monitor.
        #expect(vp.origin.x >= monitor.minX && vp.visibleRect.maxX <= monitor.maxX)
    }

    @Test func keyboardShrinkingTheVisibleAreaRecomputesCenterCell() {
        let cursor = CGPoint(x: 1720, y: 1000)
        var t = ViewportTracker(content: monitor, viewSize: CGSize(width: 1180, height: 820), scale: 1, cursor: cursor)
        let fullZone = t.viewport.deadZone
        t.relayout(content: monitor, viewSize: CGSize(width: 1180, height: 420), scale: 1, cursor: cursor)
        let zone = t.viewport.deadZone
        #expect(zone.height < fullZone.height)
        #expect(zone.minY - 0.0001 <= cursor.y && cursor.y <= zone.maxY + 0.0001)
    }

    @Test func contentSwitchCentersPointerCell() {
        var t = ViewportTracker(content: monitor, viewSize: CGSize(width: 1000, height: 600), scale: 1, cursor: CGPoint(x: 100, y: 100))
        let second = CGRect(x: 3440, y: 0, width: 2560, height: 1080)
        let cursor = CGPoint(x: 3440 + 1280, y: 540)
        t.relayout(content: second, viewSize: CGSize(width: 1000, height: 600), scale: 1, cursor: cursor)
        #expect(t.content == second)
        #expect(abs(t.viewport.visibleRect.midX - cursor.x) < 0.001)
        #expect(abs(t.viewport.visibleRect.midY - cursor.y) < 0.001)
    }
}

@Suite("View ↔ framebuffer mapping")
struct ViewportMappingTests {
    @Test func roundTrip() {
        let vp = Viewport(origin: CGPoint(x: -120.5, y: 300), scale: 0.37, viewSize: CGSize(width: 800, height: 500))
        for p in [CGPoint.zero, CGPoint(x: 1234.5, y: 77), CGPoint(x: -10, y: 4000)] {
            let back = vp.framebufferPoint(forViewPoint: vp.viewPoint(forFramebufferPoint: p))
            #expect(abs(back.x - p.x) < 0.0001)
            #expect(abs(back.y - p.y) < 0.0001)
        }
    }

    @Test func viewRectScalesSizeAndOffsetsOrigin() {
        let vp = Viewport(origin: CGPoint(x: 100, y: 50), scale: 2, viewSize: CGSize(width: 800, height: 500))
        let rect = vp.viewRect(forFramebufferRect: CGRect(x: 100, y: 50, width: 10, height: 20))
        #expect(rect == CGRect(x: 0, y: 0, width: 20, height: 40))
    }
}

@Suite("Zoom policy")
struct ZoomPolicyTests {
    @Test func fitShowsWholeContentAndFactorIsClamped() {
        let policy = ZoomPolicy(maximumPointsPerPixel: 2)
        let content = CGSize(width: 3440, height: 1440)
        let view = CGSize(width: 844, height: 390)
        let fit = ZoomPolicy.fitScale(content: content, viewSize: view)
        #expect(abs(fit - 844.0 / 3440.0) < 0.000001)
        #expect(policy.scale(forZoomFactor: 0.2, content: content, viewSize: view) == fit)
        let maxFactor = policy.maximumZoomFactor(content: content, viewSize: view)
        #expect(abs(policy.scale(forZoomFactor: 1000, content: content, viewSize: view) - 2) < 0.000001)
        #expect(maxFactor > 1)
    }
}
