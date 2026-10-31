import ScreenMateCore
import SwiftUI

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    @State private var profile: ConnectionProfile
    @State private var portText: String
    @State private var password = ""
    @State private var hadSavedPassword: Bool

    init(target: EditorTarget) {
        self.target = target
        let profile: ConnectionProfile
        switch target {
        case .new:
            profile = ConnectionProfile(name: "", host: "", username: "")
        case .existing(let existing):
            profile = existing
        }
        _profile = State(initialValue: profile)
        _portText = State(initialValue: String(profile.port))
        _hadSavedPassword = State(initialValue: profile.savesPassword)
    }

    private var issues: [ProfileIssue] { profile.issues }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("이름 (예: Mac mini)", text: $profile.name)
                    TextField("주소 또는 호스트 이름", text: $profile.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: profile.host) { _, newValue in
                            applyPastedAddress(newValue)
                        }
                    TextField("포트", text: $portText)
                        .keyboardType(.numberPad)
                        .onChange(of: portText) { _, newValue in
                            profile.port = Int(newValue) ?? 0
                        }
                }

                Section {
                    TextField("사용자 이름", text: $profile.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("암호를 Keychain에 저장", isOn: $profile.savesPassword)
                    if profile.savesPassword {
                        SecureField(hadSavedPassword ? "새 암호 (비우면 기존 암호 유지)" : "암호", text: $password)
                            .textContentType(.password)
                    }
                } header: {
                    Text("Mac 계정")
                } footer: {
                    Text("Mac 로그인 계정으로 인증합니다. 암호는 이 기기의 Keychain에만 저장되며, Mac 잠금 화면에 자동으로 입력되지 않습니다.")
                }

                Section {
                    Picker("화질", selection: $profile.quality) {
                        Text("표준 (권장)").tag(StreamQuality.standard)
                        Text("무손실").tag(StreamQuality.fullQuality)
                    }
                } footer: {
                    Text("표준은 NetBird 같은 원격 연결에서도 안정적입니다. 무손실은 빠른 같은 네트워크용입니다.")
                }

                Section {
                    Toggle("포인터를 따라 모니터 자동 전환", isOn: $profile.monitorBehavior.followsCursor)
                    Toggle("선택한 모니터 안에 포인터 가두기", isOn: $profile.monitorBehavior.confinesCursorToSelectedMonitor)
                        .disabled(profile.monitorBehavior.followsCursor)
                } header: {
                    Text("모니터")
                } footer: {
                    Text("자동 전환은 기본 꺼짐입니다. 꺼져 있으면 고른 모니터를 계속 보여 주고, 기본적으로 포인터도 그 모니터 안에 머뭅니다.")
                }

                if !issues.isEmpty, !profile.host.isEmpty || !profile.name.isEmpty {
                    Section {
                        ForEach(issues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Mac 추가" : "편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        profile.name = profile.name.trimmingCharacters(in: .whitespaces)
                        profile.host = profile.host.trimmingCharacters(in: .whitespaces)
                        profile.username = profile.username.trimmingCharacters(in: .whitespaces)
                        model.save(profile, password: password.isEmpty ? nil : password)
                        dismiss()
                    }
                    .disabled(!profile.isValid)
                }
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    /// Accept pasted `vnc://user@host:port` or `host:port`.
    private func applyPastedAddress(_ raw: String) {
        guard raw.contains(":") || raw.contains("@") else { return }
        let parsed = HostInput.parse(raw)
        guard !parsed.host.isEmpty, parsed.host != raw else { return }
        profile.host = parsed.host
        if let port = parsed.port {
            profile.port = port
            portText = String(port)
        }
        if let user = parsed.username, profile.username.isEmpty {
            profile.username = user
        }
        if profile.name.isEmpty {
            profile.name = parsed.host
        }
    }
}
