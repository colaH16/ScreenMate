import GameController
import QuartzCore
import ScreenMateCore
import ScreenMateEngine
import SwiftUI
import UIKit

/// SwiftUI wrapper. The frame it gets is exactly the area that shows the
/// remote screen, so the central-third rule uses the real visible area.
struct RemoteScreenView: UIViewControllerRepresentable {
    let controller: RemoteSessionController
    @Binding var keyboardVisible: Bool

    func makeUIViewController(context: Context) -> RemoteScreenViewController {
        let vc = RemoteScreenViewController(controller: controller)
        vc.onKeyboardVisibilityChange = { visible in
            if keyboardVisible != visible { keyboardVisible = visible }
        }
        return vc
    }

    func updateUIViewController(_ vc: RemoteScreenViewController, context: Context) {
        vc.onKeyboardVisibilityChange = { visible in
            if keyboardVisible != visible { keyboardVisible = visible }
        }
        vc.setKeyboardVisible(keyboardVisible)
    }
}

/// Draws the remote framebuffer and pointer, and turns touches, an external
/// pointer and a hardware keyboard into session input.
///
/// Touch: one finger moves the pointer (trackpad), tap = click, tap-and-a-
/// half = drag, two-finger tap = right click, two-finger drag = scroll,
/// pinch = zoom. Touch recognizers accept direct touches only and pointer
/// recognizers accept the indirect pointer only, so a mouse or trackpad on
/// iPad never produces a second, touch-derived event.
final class RemoteScreenViewController: UIViewController, UIGestureRecognizerDelegate {
    let controller: RemoteSessionController
    var onKeyboardVisibilityChange: ((Bool) -> Void)?

    private let clipLayer = CALayer()
    private let imageLayer = CALayer()
    private let cursorLayer = CALayer()
    private let fallbackCursorLayer = CAShapeLayer()
    private let keyInput = KeyInputView()

    private var displayLink: CADisplayLink?
    private var renderedImage: CGImage?
    private var renderedJump = -1
    private var renderedViewport: Viewport?
    private var renderedPointer: CGPoint?

    private var arbiter = TapDragArbiter()
    private var deadlineWork: DispatchWorkItem?
    private var lastPanTranslation = CGPoint.zero

    private var twoFinger: TwoFingerClassifier?
    private var twoFingerStartCentroid = CGPoint.zero
    private var twoFingerLastCentroid = CGPoint.zero
    private var twoFingerStartZoom: CGFloat = 1
    private var scrolling = false

    private var lastHoverLocation: CGPoint?
    private var pointerDragLast = CGPoint.zero
    private var pointerScrollLast = CGPoint.zero
    private var pinchStartZoom: CGFloat = 1
    private var mouse: GCMouse?

    init(controller: RemoteSessionController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        view.clipsToBounds = true

        clipLayer.masksToBounds = true
        clipLayer.addSublayer(imageLayer)
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.contentsGravity = .resize
        view.layer.addSublayer(clipLayer)

        fallbackCursorLayer.path = Self.arrowPath()
        fallbackCursorLayer.fillColor = UIColor.black.cgColor
        fallbackCursorLayer.strokeColor = UIColor.white.cgColor
        fallbackCursorLayer.lineWidth = 1.5
        cursorLayer.addSublayer(fallbackCursorLayer)
        cursorLayer.contentsGravity = .resize
        cursorLayer.magnificationFilter = .linear
        view.layer.addSublayer(cursorLayer)

        keyInput.controller = controller
        keyInput.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        keyInput.alpha = 0.01
        view.addSubview(keyInput)

        installTouchGestures()
        installPointerGestures()

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(mouseDidConnect),
            name: .GCMouseDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(pointerLockChanged),
            name: UIPointerLockState.didChangeNotification, object: nil)
        mouse = GCMouse.current
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if !keyInput.isFirstResponder { _ = becomeFirstResponder() }
        setNeedsUpdateOfPrefersPointerLocked()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
        deadlineWork?.cancel()
        controller.releaseEverything()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Rotation, keyboard, toolbar and iPad window resizing all land here.
        controller.resize(viewSize: view.bounds.size)
        render(force: true)
    }

    override var canBecomeFirstResponder: Bool { true }
    override var prefersPointerLocked: Bool { true }

    // MARK: - Rendering

    @objc private func tick() {
        controller.syncLayout()
        render(force: false)
    }

    private func render(force: Bool) {
        let image = controller.currentImage
        if image !== renderedImage {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = image
            CATransaction.commit()
            renderedImage = image
        }

        let screen = controller.screen
        let viewport = screen.viewport
        let pointer = screen.pointer.position
        let jump = controller.jumpGeneration
        guard force || viewport != renderedViewport || pointer != renderedPointer || jump != renderedJump else {
            updateCursorAppearance(scale: viewport.scale)
            return
        }

        CATransaction.begin()
        if jump != renderedJump, renderedJump >= 0, !force {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            // Following the pointer happens in lockstep, which already reads
            // as smooth motion; implicit animations would lag behind it.
            CATransaction.setDisableActions(true)
        }

        let layout = screen.layout
        let contentRect = viewport.viewRect(forFramebufferRect: screen.content)
        clipLayer.frame = contentRect
        let framebufferRect = viewport.viewRect(forFramebufferRect: layout.bounds)
        imageLayer.frame = framebufferRect.offsetBy(dx: -contentRect.minX, dy: -contentRect.minY)
        positionCursor(at: viewport.viewPoint(forFramebufferPoint: pointer), scale: viewport.scale)
        CATransaction.commit()

        renderedViewport = viewport
        renderedPointer = pointer
        renderedJump = jump
    }

    private var renderedCursorKey: ObjectIdentifier?

    private func updateCursorAppearance(scale: CGFloat) {
        // Shape changes (I-beam, resize arrows) arrive without pointer motion.
        let key: ObjectIdentifier? = {
            if case .image(let image, _) = controller.cursorAppearance { return ObjectIdentifier(image) }
            return nil
        }()
        if key != renderedCursorKey {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            positionCursor(at: controller.screen.viewport.viewPoint(forFramebufferPoint: controller.screen.pointer.position), scale: scale)
            CATransaction.commit()
        }
    }

    private func positionCursor(at point: CGPoint, scale: CGFloat) {
        guard !controller.screen.layout.isEmpty else {
            cursorLayer.isHidden = true
            return
        }
        switch controller.cursorAppearance {
        case .hidden:
            cursorLayer.isHidden = true
            renderedCursorKey = nil
        case .fallbackArrow:
            cursorLayer.isHidden = false
            cursorLayer.contents = nil
            fallbackCursorLayer.isHidden = false
            cursorLayer.frame = CGRect(x: point.x, y: point.y, width: 14, height: 22)
            fallbackCursorLayer.frame = cursorLayer.bounds
            renderedCursorKey = nil
        case .image(let image, let hotspot):
            cursorLayer.isHidden = false
            fallbackCursorLayer.isHidden = true
            cursorLayer.contents = image
            // Scale with zoom, but never so small it is lost or so large it
            // hides what it points at.
            let height = CGFloat(image.height)
            let target = (height * scale).clamped(18, 48)
            let factor = height > 0 ? target / height : 1
            cursorLayer.frame = CGRect(
                x: point.x - hotspot.x * factor,
                y: point.y - hotspot.y * factor,
                width: CGFloat(image.width) * factor,
                height: height * factor)
            renderedCursorKey = ObjectIdentifier(image)
        }
    }

    private static func arrowPath() -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 1, y: 17))
        path.addLine(to: CGPoint(x: 5, y: 13.5))
        path.addLine(to: CGPoint(x: 8, y: 20.5))
        path.addLine(to: CGPoint(x: 10.5, y: 19.5))
        path.addLine(to: CGPoint(x: 7.5, y: 12.5))
        path.addLine(to: CGPoint(x: 12.5, y: 12.5))
        path.close()
        return path.cgPath
    }

    // MARK: - Touch gestures

    private func installTouchGestures() {
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let pan = UIPanGestureRecognizer(target: self, action: #selector(oneFingerPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = direct
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(oneFingerTap(_:)))
        tap.numberOfTouchesRequired = 1
        tap.allowedTouchTypes = direct
        view.addGestureRecognizer(tap)

        let twoTap = UITapGestureRecognizer(target: self, action: #selector(twoFingerTap(_:)))
        twoTap.numberOfTouchesRequired = 2
        twoTap.allowedTouchTypes = direct
        view.addGestureRecognizer(twoTap)

        let twoPan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPan(_:)))
        twoPan.minimumNumberOfTouches = 2
        twoPan.maximumNumberOfTouches = 2
        twoPan.allowedTouchTypes = direct
        twoPan.delegate = self
        view.addGestureRecognizer(twoPan)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { $0.type == .direct }) {
            arbiter.touchDown(at: CACurrentMediaTime())
            deadlineWork?.cancel()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let active = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? []
        guard active.isEmpty else { return }
        // Let a tap recognizer that fires on this same lift go first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.controller.perform(self.arbiter.allTouchesLifted(at: CACurrentMediaTime()))
            self.scheduleDeadline()
        }
    }

    @objc private func oneFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        controller.perform(arbiter.tap(at: CACurrentMediaTime()))
        scheduleDeadline()
    }

    private func scheduleDeadline() {
        deadlineWork?.cancel()
        guard let deadline = arbiter.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.controller.perform(self.arbiter.deadline(at: CACurrentMediaTime()))
        }
        deadlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - CACurrentMediaTime()), execute: work)
    }

    @objc private func oneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            deadlineWork?.cancel()
            lastPanTranslation = .zero
            controller.perform(arbiter.panBegan(at: CACurrentMediaTime()))
            fallthrough
        case .changed:
            let translation = recognizer.translation(in: view)
            let delta = CGPoint(x: translation.x - lastPanTranslation.x, y: translation.y - lastPanTranslation.y)
            lastPanTranslation = translation
            let velocity = recognizer.velocity(in: view)
            controller.movePointer(viewDelta: delta, speed: hypot(velocity.x, velocity.y))
        case .ended, .cancelled, .failed:
            controller.perform(arbiter.panEnded())
        default:
            break
        }
    }

    @objc private func twoFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        deadlineWork?.cancel()
        controller.perform(arbiter.flush())
        controller.click(.right)
    }

    @objc private func twoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard recognizer.numberOfTouches == 2 else { return }
            let (centroid, span) = twoFingerGeometry(recognizer)
            twoFinger = TwoFingerClassifier(initialSpan: span)
            twoFingerStartCentroid = centroid
            twoFingerLastCentroid = centroid
            twoFingerStartZoom = controller.screen.zoomFactor
            deadlineWork?.cancel()
            controller.perform(arbiter.flush())
        case .changed:
            guard recognizer.numberOfTouches == 2, var classifier = twoFinger else { return }
            let (centroid, span) = twoFingerGeometry(recognizer)
            let translation = CGPoint(x: centroid.x - twoFingerStartCentroid.x, y: centroid.y - twoFingerStartCentroid.y)
            let intent = classifier.update(translation: translation, span: span)
            twoFinger = classifier
            switch intent {
            case .scroll:
                if !scrolling {
                    scrolling = true
                    controller.scrollBegan()
                    twoFingerLastCentroid = twoFingerStartCentroid
                }
                controller.scrollChanged(viewDelta: CGPoint(
                    x: centroid.x - twoFingerLastCentroid.x,
                    y: centroid.y - twoFingerLastCentroid.y))
                twoFingerLastCentroid = centroid
            case .zoom:
                controller.setZoomFactor(twoFingerStartZoom * classifier.zoomRatio(span: span))
            case .undecided:
                break
            }
        case .ended, .cancelled, .failed:
            if scrolling {
                scrolling = false
                controller.scrollEnded()
            }
            twoFinger = nil
        default:
            break
        }
    }

    private func twoFingerGeometry(_ recognizer: UIGestureRecognizer) -> (centroid: CGPoint, span: CGFloat) {
        let a = recognizer.location(ofTouch: 0, in: view)
        let b = recognizer.location(ofTouch: 1, in: view)
        return (CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), hypot(a.x - b.x, a.y - b.y))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }

    // MARK: - External pointer (iPad mouse / trackpad)

    private var pointerIsLocked: Bool {
        view.window?.windowScene?.pointerLockState?.isLocked ?? false
    }

    private func installPointerGestures() {
        let indirect = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(pointerHover(_:)))
        view.addGestureRecognizer(hover)

        let click = UITapGestureRecognizer(target: self, action: #selector(pointerClick(_:)))
        click.allowedTouchTypes = indirect
        click.buttonMaskRequired = .primary
        view.addGestureRecognizer(click)

        let secondary = UITapGestureRecognizer(target: self, action: #selector(pointerSecondaryClick(_:)))
        secondary.allowedTouchTypes = indirect
        secondary.buttonMaskRequired = .secondary
        view.addGestureRecognizer(secondary)

        let drag = UIPanGestureRecognizer(target: self, action: #selector(pointerDrag(_:)))
        drag.allowedTouchTypes = indirect
        view.addGestureRecognizer(drag)

        // Trackpad two-finger scroll and mouse wheel arrive as scroll events,
        // never as touches.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(pointerScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []
        view.addGestureRecognizer(scroll)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pointerPinch(_:)))
        pinch.allowedTouchTypes = indirect
        view.addGestureRecognizer(pinch)

        view.addInteraction(UIPointerInteraction(delegate: self))
    }

    @objc private func pointerHover(_ recognizer: UIHoverGestureRecognizer) {
        guard !pointerIsLocked else { return }
        let location = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            lastHoverLocation = location
        case .changed:
            if let last = lastHoverLocation {
                controller.movePointer(viewDelta: CGPoint(x: location.x - last.x, y: location.y - last.y), speed: 0)
            }
            lastHoverLocation = location
        default:
            lastHoverLocation = nil
        }
    }

    @objc private func pointerClick(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !pointerIsLocked else { return }
        controller.click(.left)
    }

    @objc private func pointerSecondaryClick(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, !pointerIsLocked else { return }
        controller.click(.right)
    }

    @objc private func pointerDrag(_ recognizer: UIPanGestureRecognizer) {
        guard !pointerIsLocked else { return }
        switch recognizer.state {
        case .began:
            pointerDragLast = .zero
            controller.setButton(.left, down: true)
        case .changed:
            let t = recognizer.translation(in: view)
            controller.movePointer(viewDelta: CGPoint(x: t.x - pointerDragLast.x, y: t.y - pointerDragLast.y), speed: 0)
            pointerDragLast = t
        default:
            controller.setButton(.left, down: false)
        }
    }

    @objc private func pointerScroll(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pointerScrollLast = .zero
            controller.scrollBegan()
        case .changed:
            let t = recognizer.translation(in: view)
            controller.scrollChanged(viewDelta: CGPoint(x: t.x - pointerScrollLast.x, y: t.y - pointerScrollLast.y))
            pointerScrollLast = t
        default:
            controller.scrollEnded()
        }
    }

    @objc private func pointerPinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchStartZoom = controller.screen.zoomFactor
        case .changed:
            controller.setZoomFactor(pinchStartZoom * recognizer.scale)
        default:
            break
        }
    }

    // Pointer lock (full-screen iPad app): raw mouse deltas let the pointer
    // keep moving past the iPad screen edge. Buttons then come from the
    // mouse itself; the UIKit pointer recognizers stand down meanwhile.

    @objc private func mouseDidConnect(_ note: Notification) {
        mouse = note.object as? GCMouse
        configureMouse()
    }

    @objc private func pointerLockChanged(_ note: Notification) {
        configureMouse()
    }

    private func configureMouse() {
        guard let input = mouse?.mouseInput else { return }
        mouse?.handlerQueue = .main
        guard pointerIsLocked else {
            input.mouseMovedHandler = nil
            input.leftButton.pressedChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            return
        }
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            self?.controller.movePointer(viewDelta: CGPoint(x: CGFloat(dx), y: CGFloat(-dy)), speed: 0)
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controller.setButton(.left, down: pressed)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controller.setButton(.right, down: pressed)
        }
    }

    // MARK: - Keyboard

    func setKeyboardVisible(_ visible: Bool) {
        if visible, !keyInput.isFirstResponder {
            _ = keyInput.becomeFirstResponder()
        } else if !visible, keyInput.isFirstResponder {
            _ = keyInput.resignFirstResponder()
            _ = becomeFirstResponder()
        }
    }

    @objc private func keyboardWillHide() {
        // The iPad keyboard-dismiss key: keep the toolbar state in sync.
        guard keyInput.isFirstResponder else { return }
        onKeyboardVisibilityChange?(false)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !KeyInputView.forward(presses, down: true, to: controller) {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !KeyInputView.forward(presses, down: false, to: controller) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !KeyInputView.forward(presses, down: false, to: controller) {
            super.pressesCancelled(presses, with: event)
        }
    }
}

extension RemoteScreenViewController: UIPointerInteractionDelegate {
    /// Hide the iPad pointer over the remote screen: the Mac's pointer is
    /// drawn instead, so there is only ever one pointer on screen.
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .hidden()
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}
