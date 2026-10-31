import ScreenMateCore
import ScreenMateEngine
import SwiftUI

/// Bottom toolbar. Keyboard, monitor selection and end session are always
/// one tap away; the special-key row appears while the keyboard is up.
struct SessionToolbar: View {
    let controller: RemoteSessionController
    @Binding var keyboardVisible: Bool
    @Binding var showingTextSheet: Bool
    @Binding var confirmEnd: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            if keyboardVisible {
                keyRow
                Divider().overlay(Color.white.opacity(0.15))
            }
            mainRow
        }
        .background(.bar)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: compact ? 4 : 12) {
            ToolButton(title: "키보드", systemImage: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard", compact: compact, isOn: keyboardVisible) {
                keyboardVisible.toggle()
            }
            monitorMenu
            Spacer(minLength: 0)
            modifierButtons
            Spacer(minLength: 0)
            moreMenu
            ToolButton(title: "종료", systemImage: "xmark.circle.fill", compact: compact, tint: .red) {
                confirmEnd = true
            }
        }
        .padding(.horizontal, compact ? 6 : 16)
        .padding(.vertical, 6)
    }

    private var monitorTitle: String {
        switch controller.selection {
        case .all: "전체"
        case .monitor(let n): "모니터 \(n)"
        }
    }

    private var monitorMenu: some View {
        Menu {
            if controller.monitors.count > 1 {
                ForEach(controller.monitors) { monitor in
                    Button {
                        controller.select(.monitor(monitor.id))
                    } label: {
                        if controller.selection == .monitor(monitor.id) {
                            Label(label(for: monitor), systemImage: "checkmark")
                        } else {
                            Text(label(for: monitor))
                        }
                    }
                }
                Button {
                    controller.select(.all)
                } label: {
                    if controller.selection == .all {
                        Label("전체 보기", systemImage: "checkmark")
                    } else {
                        Text("전체 보기")
                    }
                }
                Divider()
                Toggle("포인터 따라 자동 전환", isOn: Binding(
                    get: { controller.behavior.followsCursor },
                    set: { var b = controller.behavior; b.followsCursor = $0; controller.setBehavior(b) }))
                Toggle("선택 모니터 안에 포인터 가두기", isOn: Binding(
                    get: { controller.behavior.confinesCursorToSelectedMonitor },
                    set: { var b = controller.behavior; b.confinesCursorToSelectedMonitor = $0; controller.setBehavior(b) }))
                    .disabled(controller.behavior.followsCursor)
            } else {
                Text("모니터 1개")
            }
        } label: {
            ToolLabel(title: monitorTitle, systemImage: "display.2", compact: compact)
        }
    }

    private func label(for monitor: RemoteMonitor) -> String {
        let place: String = switch controller.placement(of: monitor) {
        case .main: "주 모니터"
        case .left: "왼쪽"
        case .right: "오른쪽"
        case .above: "위"
        case .below: "아래"
        case .overlapping: "겹침"
        }
        return "모니터 \(monitor.id) · \(place) · \(Int(monitor.frame.width))×\(Int(monitor.frame.height))"
    }

    private var modifierButtons: some View {
        HStack(spacing: compact ? 2 : 6) {
            ForEach(ModifierKey.allCases, id: \.self) { key in
                let armed = controller.armedModifiers.contains(key)
                Button {
                    controller.toggle(key)
                } label: {
                    Text(key.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: compact ? 30 : 38, height: 30)
                        .background(armed ? Color.accentColor : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("\(key.title) \(armed ? "켜짐" : "")")
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showingTextSheet = true
            } label: {
                Label("텍스트 보내기 (한글·붙여넣기)", systemImage: "text.bubble")
            }
            Menu("Mac 단축키") {
                ForEach(MacShortcut.allCases, id: \.self) { shortcut in
                    Button(shortcut.title) { controller.send(shortcut) }
                }
            }
            Menu("특수 키") {
                Button("esc") { controller.tap(.escape) }
                ForEach(SpecialKey.navigation, id: \.self) { key in
                    Button(key.label) { controller.tap(key) }
                }
                Menu("F1–F12") {
                    ForEach(SpecialKey.functionKeys, id: \.self) { key in
                        Button(key.label) { controller.tap(key) }
                    }
                }
            }
            Divider()
            Button {
                controller.refresh()
            } label: {
                Label("화면 새로고침 (복구용)", systemImage: "arrow.clockwise")
            }
        } label: {
            ToolLabel(title: "더보기", systemImage: "ellipsis.circle", compact: compact)
        }
    }

    // MARK: - Key row (keyboard up)

    private var keyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                KeyCap(label: SpecialKey.escape.label) { controller.tap(.escape) }
                KeyCap(label: SpecialKey.tab.label) { controller.tap(.tab) }
                ForEach(SpecialKey.arrows, id: \.self) { key in
                    KeyCap(label: key.label) { controller.tap(key) }
                }
                KeyCap(label: "⌃Space 한/영") { controller.send(.switchInputSource) }
                Menu {
                    ForEach(SpecialKey.functionKeys, id: \.self) { key in
                        Button(key.label) { controller.tap(key) }
                    }
                } label: {
                    KeyCapLabel(label: "F1–F12")
                }
                KeyCap(label: "텍스트 보내기") { showingTextSheet = true }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    let compact: Bool
    var isOn = false
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolLabel(title: title, systemImage: systemImage, compact: compact, tint: isOn ? .accentColor : tint)
        }
    }
}

private struct ToolLabel: View {
    let title: String
    let systemImage: String
    let compact: Bool
    var tint: Color = .white

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 2) {
                    Image(systemName: systemImage).font(.system(size: 18))
                    Text(title).font(.system(size: 10))
                }
                .frame(minWidth: 44, minHeight: 40)
            } else {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
            }
        }
        .foregroundStyle(tint)
        .contentShape(Rectangle())
    }
}

private struct KeyCap: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { KeyCapLabel(label: label) }
    }
}

private struct KeyCapLabel: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 12)
            .frame(minWidth: 40, minHeight: 34)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.white)
    }
}
