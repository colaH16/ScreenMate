import ScreenMateCore
import SwiftUI

/// Asks for the Mac account password before connecting.
struct PasswordPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let profile: ConnectionProfile
    @State private var password = ""
    @State private var remember: Bool
    @FocusState private var focused: Bool

    init(profile: ConnectionProfile) {
        self.profile = profile
        _remember = State(initialValue: profile.savesPassword)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Mac", value: profile.name)
                    LabeledContent("주소", value: profile.displayAddress)
                    LabeledContent("사용자", value: profile.username)
                }
                Section {
                    SecureField("Mac 계정 암호", text: $password)
                        .textContentType(.password)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(connect)
                    Toggle("Keychain에 저장", isOn: $remember)
                } footer: {
                    Text("화면 공유 로그인에만 쓰입니다. Mac 잠금 화면은 연결 후 키보드로 직접 해제하세요.")
                }
            }
            .navigationTitle("로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("연결", action: connect)
                        .disabled(password.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func connect() {
        guard !password.isEmpty else { return }
        let typed = password
        password = ""
        dismiss()
        model.connect(profile, password: typed, remember: remember)
    }
}
