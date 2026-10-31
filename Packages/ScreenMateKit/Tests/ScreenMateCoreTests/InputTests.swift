import CoreGraphics
import Foundation
import Testing
@testable import ScreenMateCore

/// Confirmed behavior 2: relative (trackpad) pointer by default.
@Suite("Trackpad pointer")
struct TrackpadPointerTests {
    let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    var clamp: (CGPoint) -> CGPoint { { [screen] in screen.clampedPixelPoint($0) } }

    @Test func liftingAndTouchingElsewhereContinuesFromCurrentPointer() {
        var p = TrackpadPointer(position: CGPoint(x: 1000, y: 500), settings: PointerSettings(acceleration: 0))
        // Stroke 1 starts near the left edge of the phone…
        p.move(byViewDelta: CGPoint(x: 40, y: 0), speed: 100, scale: 1, clamp: clamp)
        // …stroke 2 starts on the far right of the phone. Only deltas count.
        p.move(byViewDelta: CGPoint(x: 40, y: 10), speed: 100, scale: 1, clamp: clamp)
        #expect(p.position == CGPoint(x: 1080, y: 510))
    }

    @Test func pointerMovesByScreenDistanceSoZoomingInIsMorePrecise() {
        var zoomedOut = TrackpadPointer(position: .zero, settings: PointerSettings(acceleration: 0))
        var zoomedIn = TrackpadPointer(position: .zero, settings: PointerSettings(acceleration: 0))
        zoomedOut.move(byViewDelta: CGPoint(x: 10, y: 0), speed: 50, scale: 0.25, clamp: clamp)
        zoomedIn.move(byViewDelta: CGPoint(x: 10, y: 0), speed: 50, scale: 2, clamp: clamp)
        #expect(zoomedOut.position.x == 40)
        #expect(zoomedIn.position.x == 5)
    }

    @Test func slowMovementIsUnacceleratedAndGainNeverDecreasesWithSpeed() {
        let settings = PointerSettings(sensitivity: 1, acceleration: 0.6)
        #expect(settings.gain(forSpeed: 0) == 1)
        #expect(settings.gain(forSpeed: 200) == 1)
        var last: CGFloat = 0
        for speed in stride(from: 0.0, through: 5000.0, by: 50.0) {
            let g = settings.gain(forSpeed: CGFloat(speed))
            #expect(g >= last)
            last = g
        }
        #expect(abs(last - (1 + 0.6 * 1.5)) < 0.000001)
        #expect(PointerSettings(acceleration: 0).gain(forSpeed: 4000) == 1)
    }

    @Test func pointerStopsAtScreenEdgeAndSendsWholePixels() {
        var p = TrackpadPointer(position: CGPoint(x: 3430, y: 5))
        p.move(byViewDelta: CGPoint(x: 500, y: -500), speed: 3000, scale: 1, clamp: clamp)
        #expect(p.position == CGPoint(x: 3439, y: 0))
        #expect(p.pixel.x == 3439 && p.pixel.y == 0)
        var q = TrackpadPointer(position: CGPoint(x: 10.9, y: 20.2))
        #expect(q.pixel.x == 10 && q.pixel.y == 20)
        q.warp(to: CGPoint(x: -5, y: 99999), clamp: clamp)
        #expect(q.pixel.x == 0 && q.pixel.y == 1439)
    }
}

/// Confirmed behavior 4: two-finger drag scrolls on both axes.
@Suite("Two-finger scroll")
struct ScrollAccumulatorTests {
    @Test func verticalHorizontalAndDiagonal() {
        var acc = ScrollAccumulator()
        let down = acc.consume(viewDelta: CGPoint(x: 0, y: 25), gain: 1)
        #expect(down.pointDeltaX == 0 && down.pointDeltaY == 25)
        let left = acc.consume(viewDelta: CGPoint(x: -18, y: 0), gain: 1)
        #expect(left.pointDeltaX == -18 && left.pointDeltaY == 0)
        let diagonal = acc.consume(viewDelta: CGPoint(x: 12, y: -12), gain: 1)
        #expect(diagonal.pointDeltaX == 12 && diagonal.pointDeltaY == -12)
    }

    @Test func signFollowsTheFingersNaturalScrolling() {
        var acc = ScrollAccumulator()
        let sample = acc.consume(viewDelta: CGPoint(x: 3, y: 40), gain: 1)
        #expect(sample.pointDeltaY > 0)
        #expect(sample.wheelDeltaY > 0)
    }

    @Test func smallDeltasAreNotLostOrInflated() {
        var acc = ScrollAccumulator()
        var totalPoints = (x: Int64(0), y: Int64(0))
        var totalWheel = (x: Int64(0), y: Int64(0))
        for _ in 0..<1000 {
            let s = acc.consume(viewDelta: CGPoint(x: 0.3, y: -0.7), gain: 1)
            totalPoints.x += Int64(s.pointDeltaX)
            totalPoints.y += Int64(s.pointDeltaY)
            totalWheel.x += Int64(s.wheelDeltaX)
            totalWheel.y += Int64(s.wheelDeltaY)
        }
        #expect(abs(totalPoints.x - 300) <= 1)
        #expect(abs(totalPoints.y + 700) <= 1)
        // Whole wheel units arrive once per 10 points, never per sample.
        #expect(abs(totalWheel.x - 30) <= 1)
        #expect(abs(totalWheel.y + 70) <= 1)
    }

    @Test func gainScalesWithZoomWithinBounds() {
        #expect(ScrollAccumulator.gain(scale: 2) == 1)
        #expect(ScrollAccumulator.gain(scale: 1) == 1)
        #expect(ScrollAccumulator.gain(scale: 0.5) == 2)
        #expect(ScrollAccumulator.gain(scale: 0.1) == 4)
        #expect(ScrollAccumulator.gain(scale: 0.5, sensitivity: 1.5) == 3)
    }

    @Test func resetClearsCarriedFractions() {
        var acc = ScrollAccumulator()
        _ = acc.consume(viewDelta: CGPoint(x: 0.9, y: 9.9), gain: 1)
        acc.reset()
        let s = acc.consume(viewDelta: CGPoint(x: 0.2, y: 0.2), gain: 1)
        #expect(s.isZero)
    }
}

@Suite("Two-finger intent")
struct TwoFingerClassifierTests {
    @Test func translationIsScrollAndStaysScroll() {
        var c = TwoFingerClassifier(initialSpan: 120)
        do { let r = c.update(translation: CGPoint(x: 2, y: 3), span: 121); #expect(r == .undecided) }
        do { let r = c.update(translation: CGPoint(x: 4, y: 14), span: 124); #expect(r == .scroll) }
        // Later span change does not turn it into a zoom.
        do { let r = c.update(translation: CGPoint(x: 4, y: 20), span: 300); #expect(r == .scroll) }
    }

    @Test func spreadingIsZoomAndStaysZoom() {
        var c = TwoFingerClassifier(initialSpan: 120)
        do { let r = c.update(translation: CGPoint(x: 1, y: 2), span: 140); #expect(r == .zoom) }
        do { let r = c.update(translation: CGPoint(x: 80, y: 0), span: 140); #expect(r == .zoom) }
        #expect(abs(c.zoomRatio(span: 180) - 1.5) < 0.0001)
    }
}

/// Confirmed behavior 8: tap = left click; double-click and drag do not
/// collide with plain pointer movement.
@Suite("Tap, double-click, drag")
struct TapDragArbiterTests {
    @Test func singleTapClicksAfterWindow() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        do { let r = a.tap(at: 0.08); #expect(r == []) }
        #expect(a.nextDeadline == 0.33)
        do { let r = a.deadline(at: 0.2); #expect(r == []) }
        do { let r = a.deadline(at: 0.33); #expect(r == [.click]) }
        do { let r = a.deadline(at: 0.5); #expect(r == []) }
    }

    @Test func doubleTapIsDoubleClick() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        do { let r = a.tap(at: 0.08); #expect(r == []) }
        a.touchDown(at: 0.2)
        #expect(a.nextDeadline == nil)
        do { let r = a.tap(at: 0.27); #expect(r == [.click, .click]) }
        do { let r = a.deadline(at: 1); #expect(r == []) }
    }

    @Test func tapAndAHalfDragsWithoutAPrecedingClick() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        _ = a.tap(at: 0.08)
        a.touchDown(at: 0.25)
        do { let r = a.panBegan(at: 0.4); #expect(r == [.pressDown]) }
        #expect(a.isDragging)
        do { let r = a.panEnded(); #expect(r == [.release]) }
        do { let r = a.allTouchesLifted(at: 1); #expect(r == []) }
    }

    @Test func plainMovementNeverClicksOrDrags() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        do { let r = a.panBegan(at: 0.05); #expect(r == []) }
        do { let r = a.panEnded(); #expect(r == []) }
        do { let r = a.allTouchesLifted(at: 0.6); #expect(r == []) }
    }

    @Test func tapThenMovingAfterWindowDoesNotDrag() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        _ = a.tap(at: 0.05)
        do { let r = a.deadline(at: 0.3); #expect(r == [.click]) }
        a.touchDown(at: 0.6)
        do { let r = a.panBegan(at: 0.7); #expect(r == []) }
    }

    @Test func secondTouchHeldStillThenLiftedStillClicksOnce() {
        var a = TapDragArbiter(window: 0.25)
        a.touchDown(at: 0)
        _ = a.tap(at: 0.05)
        a.touchDown(at: 0.2)
        do { let r = a.deadline(at: 0.5); #expect(r == []) }
        do { let r = a.allTouchesLifted(at: 1.5); #expect(r == [.click]) }
        do { let r = a.deadline(at: 2); #expect(r == []) }
    }

    @Test func otherGesturesFlushHeldClickFirst() {
        var a = TapDragArbiter(window: 0.25)
        _ = a.tap(at: 0)
        do { let r = a.flush(); #expect(r == [.click]) }
        do { let r = a.flush(); #expect(r == []) }
    }
}
