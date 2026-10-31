import ScreenMateCore
import ScreenMateEngine
import SwiftUI

/// Full-screen session: the remote screen above, an always-visible toolbar
/// below (keyboard, monitor, end session), status cards on top.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    let controller: RemoteSessionController

    @State private var keyboardVisible = false
    @State private var showingTextSheet = false
    @State private var confirmEnd = false
    @State private var passwordForRetry = ""
    @State private var askingPassword = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                RemoteScreenView(controller: controller, keyboardVisible: $keyboardVisible)
                overlays
            }
            SessionToolbar(
                controller: controller,
                keyboardVisible: $keyboardVisible,
                showingTextSheet: $showingTextSheet,
                confirmEnd: $confirmEnd,
                compact: sizeClass != .regular)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.releaseEverything() }
        }
        .sheet(isPresented: $showingTextSheet) {
            TextSendSheet(controller: controller)
        }
        .confirmationDialog("연결을 종료할까요?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("연결 종료", role: .destructive) { model.endSession() }
        }
        .alert("Mac 계정 암호", isPresented: $askingPassword) {
            SecureField("암호", text: $passwordForRetry)
            Button("연결") {
                let typed = passwordForRetry
                passwordForRetry = ""
                Task { await controller.connect(password: typed) }
            }
            Button("취소", role: .cancel) { passwordForRetry = "" }
        }
    }

    @ViewBuilder
    private var overlays: some View {
        switch controller.status {
        case .idle, .connecting:
            StatusCard {
                ProgressView().controlSize(.large).tint(.white)
                Text("\(controller.profile.name)에 연결 중…").font(.headline)
                if case .connecting(let phase?) = controller.status {
                    Text(Self.phaseText(phase)).font(.subheadline).foregroundStyle(.secondary)
                }
                Button("취소", role: .cancel) { model.endSession() }
                    .buttonStyle(.bordered)
            }
        case .reconnecting(let attempt, _):
            VStack {
                Label("연결이 끊겨 다시 연결하는 중 (\(attempt)/\(controller.maximumReconnectAttempts))", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                Spacer()
            }
        case .failed(let failure):
            StatusCard {
                Image(systemName: failure.kind == .authentication ? "lock.slash" : "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(failure.title).font(.headline)
                Text(failure.suggestion)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                if !failure.detail.isEmpty {
                    Text(failure.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                HStack {
                    Button("닫기", role: .cancel) { model.endSession() }
                        .buttonStyle(.bordered)
                    Button(controller.canRetryWithoutPassword ? "다시 연결" : "암호 입력") {
                        if controller.canRetryWithoutPassword {
                            Task { await controller.retry() }
                        } else {
                            askingPassword = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .disconnected:
            StatusCard {
                Text("연결이 종료되었습니다").font(.headline)
                Button("닫기") { model.endSession() }.buttonStyle(.borderedProminent)
            }
        case .connected:
            if controller.currentImage == nil {
                StatusCard {
                    ProgressView().tint(.white)
                    Text("화면을 받는 중…").font(.subheadline)
                }
                .allowsHitTesting(false)
            } else if let hidden = controller.pointerOnHiddenMonitor {
                VStack {
                    Spacer()
                    Button {
                        controller.select(.monitor(hidden))
                    } label: {
                        Label("포인터가 모니터 \(hidden)에 있습니다 · 보기", systemImage: "cursorarrow.rays")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private static func phaseText(_ phase: String) -> String {
        switch phase {
        case "Opening connection…": "네트워크 연결 중…"
        case "Negotiating protocol…": "화면 공유 프로토콜 확인 중…"
        case "Negotiating security…": "보안 방식 협상 중…"
        case "Authenticating…": "Mac 계정 인증 중…"
        default: phase
        }
    }
}

private struct StatusCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) { content }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .environment(\.colorScheme, .dark)
            .padding(24)
    }
}
