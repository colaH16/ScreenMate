import ScreenMateEngine
import SwiftUI

/// Compose text with any iOS keyboard (한글 included), then send it.
///
/// "붙여넣기" sets the Mac clipboard and presses ⌘V: works for Hangul, emoji
/// and long text regardless of the Mac's input source, but replaces the
/// Mac's clipboard. "키 입력" types ASCII as key presses (for fields that
/// block pasting, such as some password prompts).
struct TextSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    let controller: RemoteSessionController
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isASCII: Bool { text.unicodeScalars.allSatisfy(\.isASCII) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("보낼 텍스트", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } footer: {
                    Text("붙여넣기는 Mac의 클립보드를 이 텍스트로 바꾼 뒤 ⌘V를 누릅니다. 한글·이모지는 붙여넣기로 보내세요. 키 입력은 영문·숫자·기호(ASCII)만 정확히 전달됩니다.")
                }
            }
            .navigationTitle("텍스트 보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("키 입력으로") {
                        controller.type(text)
                        dismiss()
                    }
                    .disabled(text.isEmpty || !isASCII)
                    Spacer()
                    Button("붙여넣기로 보내기") {
                        controller.paste(text)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
