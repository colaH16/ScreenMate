// screenmate-probe: live check of ScreenMate's engine against a real Mac.
//
// Verifies, with the same session setup the iOS app uses:
//   1. Mac account sign-in (Apple Screen Sharing authentication)
//   2. first frame without any manual refresh, then continuous updates
//   3. the display arrangement and client-side monitor selection
//   4. the recovery refresh
//
// The password is read from the terminal with echo off (or from stdin with
// --password-stdin). It is never accepted as an argument, printed or saved.

#if os(macOS)
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import rootshellVNC
import ScreenMateCore
import ScreenMateEngine
import UniformTypeIdentifiers

struct ProbeOptions {
    var host = "127.0.0.1"
    var port = 5900
    var user = NSUserName()
    var quality: StreamQuality = .standard
    var observeSeconds: Double = 3
    var wiggle = true
    var serverCursor = true
    var passwordFromStdin = false
    var snapshotDirectory: URL?
}

func usage() -> Never {
    print("""
    사용법: screenmate-probe [--host 주소] [--port 5900] [--user 사용자명]
                             [--quality standard|full] [--seconds 3]
                             [--no-wiggle] [--client-cursor]
                             [--snapshots 폴더] [--password-stdin]

      --no-wiggle      원격 포인터를 움직여 화면 변화를 만들지 않음
      --client-cursor  앱과 같은 클라이언트 커서 모드 (포인터 움직임이 화면 갱신을 만들지 않음)
      --snapshots      전체 화면과 모니터별 잘라낸 PNG를 이 폴더에 저장
    """)
    exit(64)
}

func parseOptions() -> ProbeOptions {
    var options = ProbeOptions()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        func value() -> String {
            guard let v = args.next() else { usage() }
            return v
        }
        switch arg {
        case "--host": options.host = value()
        case "--port": options.port = Int(value()) ?? { usage() }()
        case "--user": options.user = value()
        case "--quality":
            switch value() {
            case "standard": options.quality = .standard
            case "full": options.quality = .fullQuality
            default: usage()
            }
        case "--seconds": options.observeSeconds = Double(value()) ?? { usage() }()
        case "--no-wiggle": options.wiggle = false
        case "--client-cursor": options.serverCursor = false
        case "--password-stdin": options.passwordFromStdin = true
        case "--snapshots": options.snapshotDirectory = URL(fileURLWithPath: value(), isDirectory: true)
        case "-h", "--help": usage()
        default:
            print("알 수 없는 옵션: \(arg)")
            usage()
        }
    }
    return options
}

func readPassword(fromStdin: Bool) -> String {
    if fromStdin {
        return readLine(strippingNewline: true) ?? ""
    }
    var buffer = [CChar](repeating: 0, count: 1024)
    guard readpassphrase("Mac 계정 암호 (입력이 표시되지 않음): ", &buffer, buffer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY) != nil else {
        return ""
    }
    defer { memset_s(&buffer, buffer.count, 0, buffer.count) }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

enum Verdict: String {
    case pass = "PASS"
    case fail = "FAIL"
    case info = "INFO"
}

var results: [(Verdict, String)] = []
@MainActor
func record(_ verdict: Verdict, _ message: String) {
    results.append((verdict, message))
    print("  [\(verdict.rawValue)] \(message)")
}

@MainActor
func waitUntil(timeout: Double, _ condition: () -> Bool) async -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if condition() { return Date().timeIntervalSince(start) }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

@MainActor
func countFrames(
    _ controller: RemoteSessionController,
    seconds: Double,
    while action: ((Double) -> Void)? = nil
) async -> Int {
    var last = controller.session.currentImage.map(ObjectIdentifier.init)
    var count = 0
    let start = Date()
    while true {
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= seconds { break }
        action?(elapsed)
        let now = controller.session.currentImage.map(ObjectIdentifier.init)
        if now != last {
            count += 1
            last = now
        }
        try? await Task.sleep(for: .milliseconds(16))
    }
    return count
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func describe(_ rect: CGRect) -> String {
    "x=\(Int(rect.minX)) y=\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
}

let options = parseOptions()
print("ScreenMate probe — \(options.user)@\(options.host):\(options.port), 화질 \(options.quality.rawValue)")
var password = readPassword(fromStdin: options.passwordFromStdin)

let profile = ConnectionProfile(
    name: "probe", host: options.host, port: options.port,
    username: options.user, quality: options.quality)
let controller = RemoteSessionController(profile: profile)
if options.serverCursor {
    // Let pointer motion redraw the remote picture so update flow is
    // observable even on a still desktop.
    controller.session.configuration.cursorRendering = .server
}
controller.setPointerSettings(PointerSettings(sensitivity: 1, acceleration: 0))

print("1) 연결 및 Mac 계정 인증")
let phaseWatcher = Task { @MainActor in
    var last: String?
    while !Task.isCancelled {
        let phase = controller.session.connectionPhaseDescription
        if let phase, phase != last { print("     · \(phase)") }
        last = phase
        try? await Task.sleep(for: .milliseconds(20))
    }
}
let connectStart = Date()
await controller.connect(password: password)
password = ""
// connect() returns once the transport and sign-in are up; the engine then
// finishes starting the remote session on its own.
_ = await waitUntil(timeout: 15) {
    switch controller.status {
    case .connecting, .idle: false
    default: true
    }
}
phaseWatcher.cancel()

switch controller.status {
case .connected:
    record(.pass, String(
        format: "인증 및 연결 성공 (%.2fs), 서버 이름 \"%@\"",
        Date().timeIntervalSince(connectStart), controller.session.serverName))
case .failed(let failure):
    record(.fail, "\(failure.title) [\(failure.kind.rawValue)] — \(failure.detail)")
    print("     → \(failure.suggestion)")
    exit(failure.kind == .authentication ? 2 : 1)
default:
    record(.fail, "예상하지 못한 상태: \(controller.status)")
    exit(1)
}
if let encryption = controller.session.negotiatedContentEncryption {
    record(.info, "협상된 콘텐츠 암호화: \(encryption)")
}

print("2) 자동 화면 갱신")
if let firstFrame = await waitUntil(timeout: 10, { controller.session.currentImage != nil }) {
    record(.pass, String(
        format: "수동 Refresh 없이 첫 화면 수신 (연결 후 %.2fs), 프레임버퍼 %d×%d",
        firstFrame, controller.session.framebufferWidth, controller.session.framebufferHeight))
} else {
    record(.fail, "10초 동안 첫 화면이 오지 않음 (Mocha VNC에서 보였던 최초 갱신 멈춤 증상)")
}

_ = await waitUntil(timeout: 3) { !controller.session.remoteDisplayRegions.isEmpty }
controller.syncLayout()

let idleFrames = await countFrames(controller, seconds: options.observeSeconds)
record(.info, "가만히 있을 때 \(options.observeSeconds)s 동안 갱신 \(idleFrames)회 (정지 화면이면 0도 정상)")

if options.wiggle, !controller.screen.layout.isEmpty {
    // Small circle around the pointer's start, far from hot corners.
    var previous = CGPoint.zero
    let radius: CGFloat = 40
    let frames = await countFrames(controller, seconds: options.observeSeconds) { elapsed in
        let angle = elapsed * 2 * .pi
        let target = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        let scale = controller.screen.viewport.scale
        controller.movePointer(
            viewDelta: CGPoint(x: (target.x - previous.x) * scale, y: (target.y - previous.y) * scale),
            speed: 0)
        previous = target
    }
    if frames >= 3 {
        record(.pass, "포인터를 움직이는 \(options.observeSeconds)s 동안 연속 갱신 \(frames)회")
    } else {
        record(options.serverCursor ? .fail : .info, "포인터를 움직이는 동안 갱신 \(frames)회")
    }
}

var refreshRequested = false
let refreshFrames = await countFrames(controller, seconds: 2) { _ in
    if !refreshRequested {
        refreshRequested = true
        controller.refresh()
    }
}
record(refreshFrames > 0 ? .pass : .fail, "복구용 Refresh 요청 후 2s 동안 갱신 \(refreshFrames)회")

print("3) 모니터 배치와 선택")
let regions = controller.session.remoteDisplayRegions
record(.info, "서버가 알린 디스플레이 영역 \(regions.count)개: " + regions.map(describe).joined(separator: " | "))
let layout = controller.screen.layout
for monitor in layout.monitors {
    record(.info, "모니터 \(monitor.id) (\(layout.placement(of: monitor))): \(describe(monitor.frame))")
}
if layout.monitors.count >= 2 {
    record(.pass, "모니터 \(layout.monitors.count)개 인식")
    for target in [DisplaySelection.monitor(2), .monitor(1), .all] {
        controller.select(target)
        let content = controller.screen.content
        let pointer = controller.screen.pointer.position
        let ok = content.containsPixel(pointer) && controller.selection == target
        record(ok ? .pass : .fail, "선택 \(target): 표시 영역 \(describe(content)), 포인터 (\(Int(pointer.x)), \(Int(pointer.y)))")
    }
} else {
    record(.info, "단일 모니터로 보임 — 모니터 선택은 전체 화면 하나로 동작")
}

if let directory = options.snapshotDirectory, let image = controller.session.currentImage {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePNG(image, to: directory.appendingPathComponent("desktop-all.png"))
        for monitor in layout.monitors {
            if let crop = image.cropping(to: monitor.frame) {
                try writePNG(crop, to: directory.appendingPathComponent("monitor-\(monitor.id).png"))
            }
        }
        record(.info, "스냅샷 저장: \(directory.path)")
    } catch {
        record(.fail, "스냅샷 저장 실패: \(error.localizedDescription)")
    }
}

controller.disconnect()
_ = await waitUntil(timeout: 2) { controller.session.connectionState == .disconnected }

let failures = results.filter { $0.0 == .fail }.count
print(failures == 0 ? "결과: 모든 확인 통과" : "결과: 실패 \(failures)개")
exit(failures == 0 ? 0 : 3)
#else
print("screenmate-probe runs on macOS only.")
#endif
