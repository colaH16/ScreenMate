import CoreGraphics
import Foundation
import Observation
import RFBProtocol
import rootshellVNC
import ScreenMateCore

public enum SessionStatus: Equatable, Sendable {
    case idle
    case connecting(String?)
    case connected
    case reconnecting(attempt: Int, delay: TimeInterval)
    case disconnected
    case failed(ConnectionFailure)

    public var isLive: Bool {
        switch self {
        case .connected, .reconnecting: true
        default: false
        }
    }
}

public enum MouseButton: Sendable {
    case left
    case right

    var mask: UInt8 {
        switch self {
        case .left: 1 << 0
        case .right: 1 << 2
        }
    }
}

/// One open Mac session: the engine, what is shown, and every input path.
///
/// Views send gestures here and draw `screen`; this type turns them into
/// remote pointer, scroll and key events. `screen` is not observed on
/// purpose (it changes on every finger sample); SwiftUI observes the small
/// published values below instead, and the remote view polls `screen` once
/// per display frame.
@MainActor
@Observable
public final class RemoteSessionController {
    public let session: VNCSession
    public private(set) var profile: ConnectionProfile

    // Observed, low-frequency state for toolbars and overlays.
    public private(set) var selection: DisplaySelection
    public private(set) var monitors: [RemoteMonitor] = []
    public private(set) var behavior: MonitorBehavior
    /// Set when the pointer sits on a monitor that is not shown.
    public private(set) var pointerOnHiddenMonitor: Int?
    public private(set) var failure: ConnectionFailure?
    /// Toolbar modifier keys, applied to the next key or click, then cleared.
    public var pendingModifiers: VNCKeyboardModifiers = []

    /// Called when something worth saving changed (monitor choice, monitor
    /// behavior, last connection time).
    @ObservationIgnored public var onProfileChange: ((ConnectionProfile) -> Void)?

    @ObservationIgnored public private(set) var screen: RemoteScreenModel
    /// Bumped when the viewport jumps (monitor switch, layout change) so the
    /// view can animate instead of following in lockstep.
    @ObservationIgnored public private(set) var jumpGeneration = 0

    @ObservationIgnored private var password: String?
    @ObservationIgnored private var connectionRecorded = false
    @ObservationIgnored private var buttonMask: UInt8 = 0
    @ObservationIgnored private var heldModifierKeysyms: [UInt32] = []
    @ObservationIgnored private var scrollAccumulator = ScrollAccumulator()
    @ObservationIgnored private var scrollActive = false
    @ObservationIgnored private var hardwareKeysyms: [Int: UInt32] = [:]
    @ObservationIgnored private let keyboard: KeyboardInputHandler

    public init(
        profile: ConnectionProfile,
        viewSize: CGSize = CGSize(width: 1024, height: 768),
        pointerSettings: PointerSettings = .default
    ) {
        let session = VNCSession(configuration: SessionSetup.configuration(for: profile))
        self.session = session
        self.profile = profile
        self.selection = profile.lastSelection
        self.behavior = profile.monitorBehavior
        self.screen = RemoteScreenModel(
            layout: .empty,
            selection: profile.lastSelection,
            behavior: profile.monitorBehavior,
            viewSize: viewSize,
            pointerSettings: pointerSettings)
        self.keyboard = KeyboardInputHandler(
            sendKeyEvent: { [session] down, keysym in
                session.sendKeyEvent(downFlag: down, key: keysym)
            },
            usesAppleModifierConvention: { [session] in
                session.serverUsesAppleModifierConvention
            })
    }

    // MARK: - Connection

    public var status: SessionStatus {
        switch session.connectionState {
        case .idle:
            return failure.map(SessionStatus.failed) ?? .idle
        case .connecting:
            return .connecting(session.connectionPhaseDescription)
        case .connected:
            return .connected
        case .reconnecting(let attempt, let delay):
            return .reconnecting(attempt: attempt, delay: delay)
        case .disconnecting, .disconnected:
            return failure.map(SessionStatus.failed) ?? .disconnected
        case .failed(let message):
            if let failure { return .failed(failure) }
            if let lastError = session.lastError {
                return .failed(ConnectionFailure.classify(protocolError: lastError))
            }
            return .failed(ConnectionFailure(kind: .network, detail: message))
        }
    }

    public var maximumReconnectAttempts: Int { SessionSetup.reconnectionPolicy.maximumAttempts }

    /// Whether `retry()` can run without asking for the password again.
    public var canRetryWithoutPassword: Bool { password != nil }

    /// Sign in with the Mac account. The password is kept in memory only
    /// while this session is open, for manual retries.
    ///
    /// Returns once the transport and sign-in are up; the engine finishes
    /// starting the remote session afterwards, so watch `status` for
    /// `.connected`.
    public func connect(password: String) async {
        self.password = password
        failure = nil
        connectionRecorded = false
        do {
            try await session.connect(credentials: SessionSetup.credentials(for: profile, password: password))
            syncLayout()
        } catch {
            failure = ConnectionFailure.classify(error)
            if failure?.kind == .authentication {
                self.password = nil
            }
        }
    }

    public func retry() async {
        guard let password else { return }
        await connect(password: password)
    }

    public func disconnect() {
        password = nil
        releaseEverything()
        session.disconnect()
    }

    /// Recovery only: ask the Mac to resend the whole screen.
    public func refresh() {
        session.requestFullRefresh()
    }

    // MARK: - Layout and view geometry

    /// Pull the Mac's current framebuffer and display arrangement into the
    /// screen model. Cheap; the remote view calls it every display frame.
    public func syncLayout() {
        let size = CGSize(width: session.framebufferWidth, height: session.framebufferHeight)
        let layout = MonitorLayout(serverRegions: session.remoteDisplayRegions, framebufferSize: size)
        guard layout != screen.layout else { return }
        screen.updateLayout(layout)
        jumpGeneration += 1
        if !layout.isEmpty, !connectionRecorded, session.connectionState.isConnected {
            // The session really came up: remember it for list ordering.
            connectionRecorded = true
            profile.lastConnectedAt = Date()
            onProfileChange?(profile)
        }
        publish()
        // Put the Mac's pointer where ours is drawn (first frame, reconnect,
        // or a display change that clamped the pointer).
        sendPointer()
    }

    public func resize(viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        screen.resize(viewSize: viewSize)
    }

    public func setZoomFactor(_ factor: CGFloat) {
        screen.setZoomFactor(factor)
    }

    public func select(_ newSelection: DisplaySelection) {
        screen.select(newSelection)
        jumpGeneration += 1
        sendPointer()
        publish()
    }

    public func setBehavior(_ newBehavior: MonitorBehavior) {
        screen.setBehavior(newBehavior)
        sendPointer()
        publish()
    }

    public func setPointerSettings(_ settings: PointerSettings) {
        screen.setPointerSettings(settings)
    }

    private func publish() {
        if selection != screen.selection { selection = screen.selection }
        if monitors != screen.layout.monitors { monitors = screen.layout.monitors }
        if behavior != screen.behavior { behavior = screen.behavior }
        let hidden = screen.isPointerInContent ? nil : screen.pointerMonitor?.id
        if pointerOnHiddenMonitor != hidden { pointerOnHiddenMonitor = hidden }

        var changed = profile
        changed.lastSelection = screen.selection
        changed.monitorBehavior = screen.behavior
        if changed != profile {
            profile = changed
            onProfileChange?(changed)
        }
    }

    public func placement(of monitor: RemoteMonitor) -> MonitorPlacement {
        screen.layout.placement(of: monitor)
    }

    // MARK: - Pointer

    /// Trackpad movement from a finger, in view points.
    public func movePointer(viewDelta: CGPoint, speed: CGFloat) {
        let result = screen.movePointer(byViewDelta: viewDelta, speed: speed)
        if result.selectionChanged { jumpGeneration += 1 }
        sendPointer()
        publishPointerState(selectionChanged: result.selectionChanged)
    }

    private func publishPointerState(selectionChanged: Bool) {
        if selectionChanged {
            publish()
            return
        }
        let hidden = screen.isPointerInContent ? nil : screen.pointerMonitor?.id
        if pointerOnHiddenMonitor != hidden { pointerOnHiddenMonitor = hidden }
    }

    public func perform(_ actions: [PointerAction]) {
        for action in actions {
            switch action {
            case .click:
                click(.left)
            case .pressDown:
                setButton(.left, down: true)
            case .release:
                setButton(.left, down: false)
            }
        }
    }

    public func click(_ button: MouseButton, count: Int = 1) {
        let modifiers = takeModifierKeysyms()
        modifiers.forEach { session.sendKeyEvent(downFlag: true, key: $0) }
        for _ in 0..<max(1, count) {
            buttonMask |= button.mask
            sendPointer()
            buttonMask &= ~button.mask
            sendPointer()
        }
        modifiers.reversed().forEach { session.sendKeyEvent(downFlag: false, key: $0) }
    }

    /// Hold or release a button (drags, external mouse buttons). Toolbar
    /// modifiers taken at press time stay held until release.
    public func setButton(_ button: MouseButton, down: Bool) {
        if down {
            guard buttonMask & button.mask == 0 else { return }
            if buttonMask == 0 {
                heldModifierKeysyms = takeModifierKeysyms()
                heldModifierKeysyms.forEach { session.sendKeyEvent(downFlag: true, key: $0) }
            }
            buttonMask |= button.mask
            sendPointer()
        } else {
            guard buttonMask & button.mask != 0 else { return }
            buttonMask &= ~button.mask
            sendPointer()
            if buttonMask == 0 {
                heldModifierKeysyms.reversed().forEach { session.sendKeyEvent(downFlag: false, key: $0) }
                heldModifierKeysyms = []
            }
        }
    }

    private func sendPointer() {
        guard session.connectionState.isConnected, !screen.layout.isEmpty else { return }
        let pixel = screen.pointer.pixel
        session.sendPointerEvent(buttonMask: buttonMask, x: pixel.x, y: pixel.y)
    }

    // MARK: - Scroll

    private static let scrollFlags: AppleScrollEvent.Flags = [.continuous, .directionInvertedFromDevice]

    public func scrollBegan() {
        if scrollActive { scrollEnded() }
        scrollActive = true
        scrollAccumulator.reset()
        guard session.connectionState.isConnected else { return }
        let p = screen.pointer.pixel
        session.sendGestureEvent(AppleGestureEvent(kind: .began, x: p.x, y: p.y))
        session.sendScrollEvent(AppleScrollEvent(scrollPhase: .began, flags: Self.scrollFlags, x: p.x, y: p.y))
    }

    /// Two-finger movement in view points. Both axes are sent together.
    public func scrollChanged(viewDelta: CGPoint) {
        guard scrollActive else { return }
        let sample = scrollAccumulator.consume(
            viewDelta: viewDelta,
            gain: ScrollAccumulator.gain(scale: screen.viewport.scale))
        guard !sample.isZero, session.connectionState.isConnected else { return }
        let p = screen.pointer.pixel
        session.sendScrollEvent(AppleScrollEvent(
            deltaX: sample.wheelDeltaX,
            deltaY: sample.wheelDeltaY,
            fixedDeltaX: sample.fixedDeltaX,
            fixedDeltaY: sample.fixedDeltaY,
            pointDeltaX: sample.pointDeltaX,
            pointDeltaY: sample.pointDeltaY,
            scrollPhase: .changed,
            flags: Self.scrollFlags,
            x: p.x,
            y: p.y))
    }

    public func scrollEnded() {
        guard scrollActive else { return }
        scrollActive = false
        guard session.connectionState.isConnected else { return }
        let p = screen.pointer.pixel
        session.sendScrollEvent(AppleScrollEvent(scrollPhase: .ended, flags: Self.scrollFlags, x: p.x, y: p.y))
        session.sendGestureEvent(AppleGestureEvent(kind: .ended, x: p.x, y: p.y))
    }

    // MARK: - Keyboard

    private func takeModifierKeysyms() -> [UInt32] {
        guard !pendingModifiers.isEmpty else { return [] }
        let keysyms = KeyboardInputHandler.keysyms(
            for: pendingModifiers,
            appleModifierConvention: session.serverUsesAppleModifierConvention)
        pendingModifiers = []
        return keysyms
    }

    private func takeModifiers() -> VNCKeyboardModifiers {
        let modifiers = pendingModifiers
        pendingModifiers = []
        return modifiers
    }

    public func toggleModifier(_ modifier: VNCKeyboardModifiers) {
        if pendingModifiers.contains(modifier) {
            pendingModifiers.remove(modifier)
        } else {
            pendingModifiers.insert(modifier)
        }
    }

    /// Text from the on-screen keyboard, typed as key presses. Toolbar
    /// modifiers apply to the first character only (⌘ then "c" is ⌘C).
    public func type(_ text: String) {
        var modifiers = takeModifiers()
        for character in text {
            if character == "\n" || character == "\r" {
                keyboard.handleKeysymTap(KeyboardInputHandler.keysymReturn, supplementalModifiers: modifiers)
            } else if character == "\t" {
                keyboard.handleKeysymTap(KeyboardInputHandler.keysymTab, supplementalModifiers: modifiers)
            } else {
                keyboard.handleKeyTap(character, supplementalModifiers: modifiers)
            }
            modifiers = []
        }
    }

    public func tapKey(_ keysym: UInt32) {
        keyboard.handleKeysymTap(keysym, supplementalModifiers: takeModifiers())
    }

    /// A shortcut chord held for a moment, so the Mac's window server sees a
    /// real combination (⌘Tab, ⌃Space) rather than an instant blip.
    func tapKey(_ keysym: UInt32, extraModifiers: VNCKeyboardModifiers) {
        let modifiers = KeyboardInputHandler.keysyms(
            for: takeModifiers().union(extraModifiers),
            appleModifierConvention: session.serverUsesAppleModifierConvention)
        modifiers.forEach { session.sendKeyEvent(downFlag: true, key: $0) }
        session.sendKeyEvent(downFlag: true, key: keysym)
        let session = self.session
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            session.sendKeyEvent(downFlag: false, key: keysym)
            modifiers.reversed().forEach { session.sendKeyEvent(downFlag: false, key: $0) }
        }
    }

    public func shortcut(_ character: Character, modifiers: VNCKeyboardModifiers) {
        keyboard.handleShortcutTap(character, modifiers: modifiers)
    }

    /// Paste arbitrary text (Hangul, emoji, long strings) through the Mac's
    /// clipboard, then ⌘V. Replaces the Mac's clipboard contents.
    public func paste(_ text: String) {
        guard !text.isEmpty, session.connectionState.isConnected else { return }
        session.sendClipboardText(text)
        keyboard.handleShortcutTap("v", modifiers: .command)
    }

    /// A hardware keyboard key, by HID usage. Key-up reuses the keysym sent
    /// on key-down even if modifiers changed in between.
    public func hardwareKey(usage: Int, characters: String, down: Bool) {
        if down {
            let keysym = KeyboardInputHandler.keysymForHIDUsage(
                UInt32(clamping: usage),
                characters: characters,
                appleModifierConvention: session.serverUsesAppleModifierConvention)
            guard keysym != 0 else { return }
            hardwareKeysyms[usage] = keysym
            keyboard.handleKeysym(downFlag: true, keysym: keysym)
        } else if let keysym = hardwareKeysyms.removeValue(forKey: usage) {
            keyboard.handleKeysym(downFlag: false, keysym: keysym)
        }
    }

    /// Release every held key and button, for focus loss and teardown, so the
    /// Mac never keeps a stuck modifier.
    public func releaseEverything() {
        for keysym in hardwareKeysyms.values {
            keyboard.handleKeysym(downFlag: false, keysym: keysym)
        }
        hardwareKeysyms = [:]
        if scrollActive { scrollEnded() }
        if buttonMask != 0 {
            buttonMask = 0
            sendPointer()
        }
        heldModifierKeysyms.reversed().forEach { session.sendKeyEvent(downFlag: false, key: $0) }
        heldModifierKeysyms = []
    }
}
