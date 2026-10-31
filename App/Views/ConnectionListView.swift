import ScreenMateCore
import SwiftUI

/// Saved Macs. iPhone shows a list; iPad (regular width) shows a grid of
/// larger cards. One tap connects.
struct ConnectionListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var editing: EditorTarget?
    @State private var passwordPrompt: ConnectionProfile?
    @State private var pendingDelete: ConnectionProfile?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.profiles.isEmpty {
                    emptyState
                } else if sizeClass == .regular {
                    grid
                } else {
                    list
                }
            }
            .navigationTitle("ScreenMate")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = .new
                    } label: {
                        Label("Mac 추가", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            ProfileEditorView(target: target)
                .environment(model)
        }
        .sheet(item: $passwordPrompt) { profile in
            PasswordPromptView(profile: profile)
                .environment(model)
        }
        .fullScreenCover(item: $model.activeSession) { session in
            SessionView(controller: session.controller)
                .environment(model)
        }
        .confirmationDialog(
            "‘\(pendingDelete?.name ?? "")’을(를) 삭제할까요?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let pendingDelete { model.delete(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text("저장된 암호도 Keychain에서 함께 지워집니다.")
        }
        .alert("저장 오류", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(model.storageError ?? "")
        }
    }

    private func connect(_ profile: ConnectionProfile) {
        if !model.connectWithSavedPassword(profile) {
            passwordPrompt = profile
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.sortedProfiles) { profile in
                    Button {
                        connect(profile)
                    } label: {
                        ProfileRow(profile: profile, hasPassword: model.hasSavedPassword(profile))
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button("삭제", role: .destructive) { pendingDelete = profile }
                        Button("편집") { editing = .existing(profile) }.tint(.gray)
                    }
                    .contextMenu { menuItems(for: profile) }
                }
            } footer: {
                Text("Mac의 시스템 설정 › 일반 › 공유 › 화면 공유를 켜고, 접근을 허용한 Mac 계정으로 로그인합니다.")
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                ForEach(model.sortedProfiles) { profile in
                    Button {
                        connect(profile)
                    } label: {
                        ProfileCard(profile: profile, hasPassword: model.hasSavedPassword(profile))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuItems(for: profile) }
                }
            }
            .padding(24)
            Text("Mac의 시스템 설정 › 일반 › 공유 › 화면 공유를 켜고, 접근을 허용한 Mac 계정으로 로그인합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func menuItems(for profile: ConnectionProfile) -> some View {
        Button { connect(profile) } label: { Label("연결", systemImage: "play.fill") }
        Button { passwordPrompt = profile } label: { Label("암호 입력 후 연결", systemImage: "key") }
        Button { editing = .existing(profile) } label: { Label("편집", systemImage: "pencil") }
        Button(role: .destructive) { pendingDelete = profile } label: { Label("삭제", systemImage: "trash") }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("저장된 Mac 없음", systemImage: "display")
        } description: {
            Text("Mac의 주소와 사용자 이름을 추가하세요.")
        } actions: {
            Button("Mac 추가") { editing = .new }
                .buttonStyle(.borderedProminent)
        }
    }
}

enum EditorTarget: Identifiable {
    case new
    case existing(ConnectionProfile)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let profile): profile.id.uuidString
        }
    }
}

private struct ProfileRow: View {
    let profile: ConnectionProfile
    let hasPassword: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "macmini")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                Text("\(profile.username) · \(profile.displayAddress)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if hasPassword {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("암호 저장됨")
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProfileCard: View {
    let profile: ConnectionProfile
    let hasPassword: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "macmini")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Spacer()
                if hasPassword {
                    Label("암호 저장됨", systemImage: "key.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            Text(profile.name)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Label(profile.displayAddress, systemImage: "network")
                Label(profile.username, systemImage: "person")
                if let last = profile.lastConnectedAt {
                    Label(last.formatted(.relative(presentation: .named)), systemImage: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            HStack {
                Spacer()
                Text("연결")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
