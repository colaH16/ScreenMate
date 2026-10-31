# Vendored: rootshell-vnc

| 항목 | 값 |
| --- | --- |
| 원본 | https://github.com/kitknox/rootshell-vnc |
| 버전 | `v0.1.8` (태그 = 검토 시점 `main` HEAD) |
| 커밋 | `ef4d0c4f34cf2e3e6476a8a6ce5d1a2461b27c74` (2026-10-17) |
| 라이선스 | MIT, Copyright (c) 2026 Rootshell LLC, Kit Knox — `rootshell-vnc/LICENSE` 원문 유지 |
| 포함 범위 | `Package.swift`, `LICENSE`, `README.md`, `Sources/`, `Tests/` (원본 `Examples/`, `Tools/`는 제외) |

## 왜 SwiftPM 원격 의존성이 아니라 vendoring인가

ScreenMate는 Mac의 모든 모니터를 하나의 결합 데스크톱으로 받고, 모니터 1/2/전체 선택을
클라이언트에서 잘라 보여 준다(전환이 즉시, 재연결 없음). 그러려면 서버가 알려 준 디스플레이 영역이
필요한데 원본에서는 `internal`이다. 또 복구용 수동 새로고침(비증분 전체 화면 요청)을 부를 공개 API가
없다. 두 가지만 공개하는 최소 패치를 적용했다.

## 패치 (`rootshell-vnc-screenmate.patch`)

`Sources/rootshellVNC/API/VNCSession.swift`만 수정:

1. `remoteDisplayRegions`를 `public private(set)`으로 — 읽기 전용 공개.
2. `public func requestFullRefresh()` 추가 — 연결 중일 때 비증분 `FramebufferUpdateRequest`
   (High Performance 경로면 키프레임도) 1회 요청.

동작 변경은 없다. 원본 테스트 스위트는 그대로 포함되어 있다.

## 업데이트 방법

1. 새 태그를 받아 `Package.swift LICENSE README.md Sources Tests`를 덮어쓴다.
2. `patch -p1 -d Vendor/rootshell-vnc < Vendor/rootshell-vnc-screenmate.patch`
3. `Packages/ScreenMateKit`에서 `swift test`, iOS 빌드, `Tools/run-probe.sh`로 실호스트 재검증.

## 함께 빌드되는 외부 의존성 (저장소에 포함되지 않음, SwiftPM이 받음)

`Package.resolved`에 고정된 버전: BigInt 5.7.0 (MIT), swift-nio 2.95.0, swift-nio-ssl 2.36.0
(BoringSSL 포함), swift-nio-transport-services 1.26.0, swift-atomics, swift-collections,
swift-system (Apache 2.0). 앱을 배포할 때의 고지 의무는 `THIRD_PARTY_NOTICES.md` 참고.
