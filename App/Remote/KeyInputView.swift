import ScreenMateEngine
import UIKit

/// Invisible first responder that brings up the iOS keyboard and forwards
/// what it types.
///
/// The keyboard is ASCII-capable on purpose: each key press goes straight to
/// the Mac as a key event, and the Mac's own input source decides the result
/// (switch it to 한글 with ⌃Space and type 두벌식 positions, as on a physical
/// keyboard). Text composed in an iOS IME (Hangul, emoji) goes through the
/// "텍스트 보내기" sheet, which pastes via the Mac clipboard instead.
final class KeyInputView: UIView, UIKeyInput {
    weak var controller: RemoteSessionController?

    override var canBecomeFirstResponder: Bool { true }

    // UITextInputTraits
    var keyboardType: UIKeyboardType = .asciiCapable
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var inlinePredictionType: UITextInlinePredictionType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default

    override func becomeFirstResponder() -> Bool {
        // No shortcut/prediction bar above the iPad keyboard.
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        return super.becomeFirstResponder()
    }

    // Always "has text" so backspace keeps working on an empty field.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        controller?.type(text)
    }

    func deleteBackward() {
        controller?.tap(.backspace)
    }

    // A hardware keyboard reaches whichever responder is first. Handling the
    // presses here, without calling super, stops UIKit from also inserting
    // text for them, so each key reaches the Mac exactly once.

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let controller, Self.forward(presses, down: true, to: controller) else {
            return super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let controller, Self.forward(presses, down: false, to: controller) else {
            return super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let controller, Self.forward(presses, down: false, to: controller) else {
            return super.pressesCancelled(presses, with: event)
        }
    }

    /// Returns true when every press was a keyboard key and was sent.
    @MainActor
    static func forward(_ presses: Set<UIPress>, down: Bool, to controller: RemoteSessionController) -> Bool {
        let keys = presses.compactMap(\.key)
        guard !keys.isEmpty, keys.count == presses.count else { return false }
        for key in keys {
            let commandOrControl = key.modifierFlags.contains(.command) || key.modifierFlags.contains(.control)
            let characters = commandOrControl ? key.charactersIgnoringModifiers : key.characters
            controller.hardwareKey(usage: key.keyCode.rawValue, characters: characters, down: down)
        }
        return true
    }
}
