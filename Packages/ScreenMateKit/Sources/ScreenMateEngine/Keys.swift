import CoreGraphics
import rootshellVNC

/// Toolbar modifier keys. Tapping one arms it for the next key or click.
public enum ModifierKey: CaseIterable, Hashable, Sendable {
    case control
    case option
    case shift
    case command

    var flag: VNCKeyboardModifiers {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        }
    }

    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    public var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }
}

/// Keys the iOS keyboard cannot type.
public enum SpecialKey: Hashable, Sendable {
    case escape
    case tab
    case returnKey
    case backspace
    case forwardDelete
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)

    public static let arrows: [SpecialKey] = [.left, .up, .down, .right]
    public static let navigation: [SpecialKey] = [.home, .end, .pageUp, .pageDown, .forwardDelete]
    public static let functionKeys: [SpecialKey] = (1...12).map(SpecialKey.function)

    var keysym: UInt32 {
        switch self {
        case .escape: KeyboardInputHandler.keysymEscape
        case .tab: KeyboardInputHandler.keysymTab
        case .returnKey: KeyboardInputHandler.keysymReturn
        case .backspace: KeyboardInputHandler.keysymBackspace
        case .forwardDelete: KeyboardInputHandler.keysymDelete
        case .up: KeyboardInputHandler.keysymUp
        case .down: KeyboardInputHandler.keysymDown
        case .left: KeyboardInputHandler.keysymLeft
        case .right: KeyboardInputHandler.keysymRight
        case .home: KeyboardInputHandler.keysymHome
        case .end: KeyboardInputHandler.keysymEnd
        case .pageUp: KeyboardInputHandler.keysymPageUp
        case .pageDown: KeyboardInputHandler.keysymPageDown
        case .function(let n): KeyboardInputHandler.keysymForFunctionKey(n)
        }
    }

    public var label: String {
        switch self {
        case .escape: "esc"
        case .tab: "tab"
        case .returnKey: "return"
        case .backspace: "⌫"
        case .forwardDelete: "⌦"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PgUp"
        case .pageDown: "PgDn"
        case .function(let n): "F\(n)"
        }
    }
}

/// Mac shortcuts that are hard or impossible to type from iOS (the system
/// keeps ⌘Space and ⌘Tab for itself on iPad).
public enum MacShortcut: CaseIterable, Hashable, Sendable {
    /// Switch the Mac's input source (ABC ↔ 한글) with the default shortcut.
    case switchInputSource
    case spotlight
    case appSwitcher
    case missionControl

    public var title: String {
        switch self {
        case .switchInputSource: "입력 소스 전환 (⌃Space)"
        case .spotlight: "Spotlight (⌘Space)"
        case .appSwitcher: "앱 전환 (⌘Tab)"
        case .missionControl: "Mission Control (⌃↑)"
        }
    }

    var chord: (key: UInt32, modifiers: VNCKeyboardModifiers) {
        switch self {
        case .switchInputSource: (KeyboardInputHandler.keysymForCharacter(" "), .control)
        case .spotlight: (KeyboardInputHandler.keysymForCharacter(" "), .command)
        case .appSwitcher: (KeyboardInputHandler.keysymTab, .command)
        case .missionControl: (KeyboardInputHandler.keysymUp, .control)
        }
    }
}

/// How to draw the pointer.
public enum CursorAppearance {
    /// The Mac hid its pointer (for example while typing or in full-screen video).
    case hidden
    /// No shape received yet; draw ScreenMate's own arrow.
    case fallbackArrow
    /// The Mac's own cursor image and hotspot, in cursor-image pixels.
    case image(CGImage, hotspot: CGPoint)
}

extension RemoteSessionController {
    public var armedModifiers: Set<ModifierKey> {
        Set(ModifierKey.allCases.filter { pendingModifiers.contains($0.flag) })
    }

    public func toggle(_ modifier: ModifierKey) {
        toggleModifier(modifier.flag)
    }

    public func tap(_ key: SpecialKey) {
        tapKey(key.keysym)
    }

    public func send(_ shortcut: MacShortcut) {
        let chord = shortcut.chord
        tapKey(chord.key, extraModifiers: chord.modifiers)
    }

    public var currentImage: CGImage? { session.currentImage }

    public var cursorAppearance: CursorAppearance {
        switch session.remoteCursorPresence {
        case .hidden:
            return .hidden
        case .undescribed:
            return .fallbackArrow
        case .described:
            guard let cursor = session.remoteCursor else { return .fallbackArrow }
            return .image(cursor.image, hotspot: CGPoint(x: cursor.hotspotX, y: cursor.hotspotY))
        }
    }
}
