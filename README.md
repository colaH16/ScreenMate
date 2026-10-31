# ScreenMate (가칭)

아이폰·아이패드에서 **Mac 기본 화면 공유**에 접속하는 공용 네이티브 앱. 내부적으로 Apple RFB(VNC)
프로토콜을 쓰지만 대상은 macOS 화면 공유뿐이다(Windows/Linux VNC 서버는 범위 밖).

핵심: 저장한 Mac 계정으로 바로 접속 → 화면 자동 갱신 → **트랙패드식 상대 커서가 기본** →
보이는 영역의 **중앙 1/3 기준 자동 화면 추적** → 두 손가락 2축 스크롤 → 모니터 1/2/전체 수동 선택
(자동 전환 기본 OFF) → 도구모음에서 키보드·모니터·종료.

세부 결정과 근거는 [docs/DECISIONS.md](docs/DECISIONS.md). 원래 요구사항 문서(`CLAUDE_HANDOFF.md`)는
개인 네트워크 정보가 있어 저장소에서 뺐다.

## 구조

```
App/                         iOS/iPadOS 앱 (SwiftUI + UIKit 원격 화면 뷰)
  Views/                     접속 목록(iPhone 리스트 / iPad 카드 그리드), 편집, 암호, 세션, 도구모음
  Remote/                    원격 화면 렌더링·제스처·외장 포인터·하드웨어 키보드
Packages/ScreenMateKit/
  Sources/ScreenMateCore/    순수 로직: 뷰포트(중앙 1/3), 모니터 배치, 상대 포인터, 스크롤, 제스처 판정, 프로필
  Sources/ScreenMateEngine/  세션 컨트롤러: 연결/인증/재연결/오류 분류, 포인터·스크롤·키 전송
  Sources/ScreenMateProbe/   macOS CLI 실호스트 검증 도구
  Tests/                     78개 테스트
Vendor/rootshell-vnc/        RFB 엔진 v0.1.8 (MIT) + 최소 패치 — Vendor/VENDOR.md
Tools/run-probe.sh           실제 Mac 로그인·연속 갱신·모니터 확인
ScreenMate.xcodeproj         아이폰+아이패드 공용 타깃 (iOS 18+, Swift 6)
```

## 빌드와 테스트 (이 Mac)

Xcode는 `/Applications/Develop/Xcode-beta.app`(Xcode 27.2)에 있고 `xcode-select`는 Command Line
Tools를 가리킨다. 명령줄에서는 `DEVELOPER_DIR`로 지정한다(시스템 설정 변경 불필요).

로직·엔진 테스트 (macOS에서 실행):

```bash
DEVELOPER_DIR=/Applications/Develop/Xcode-beta.app/Contents/Developer swift test --package-path Packages/ScreenMateKit
```

iOS 컴파일 확인 (서명 없이):

```bash
DEVELOPER_DIR=/Applications/Develop/Xcode-beta.app/Contents/Developer xcodebuild -project ScreenMate.xcodeproj -scheme ScreenMate -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

실제 Mac 검증 (암호는 터미널에서 직접 입력, 화면에 표시·저장 안 됨):

```bash
bash Tools/run-probe.sh --host 127.0.0.1 --user <Mac 사용자명> --snapshots
```

`--snapshots`는 받은 결합 데스크톱과 모니터별로 잘라낸 PNG를 `ProbeResults/`(git 제외)에 저장한다.

## 아이폰·아이패드에 설치

서명 설정은 `Config/Signing.xcconfig`가 기본값(팀 없음, `com.example.ScreenMate`)을 두고, git에서 제외된
`Config/Signing.local.xcconfig`가 개인 팀 ID와 번들 ID 접두사로 덮어쓴다. 새로 받은 저장소라면 이 파일을
만든다(`Signing.xcconfig` 주석 참고). 개발한 Mac에는 이미 만들어 두었다.

직접 해야 하는 것:

1. `ScreenMate.xcodeproj`를 Xcode-beta로 연다.
2. Xcode › Settings › Accounts에 `Signing.local.xcconfig`의 팀에 속한 Apple 계정을 로그인한다.
3. 아이폰/아이패드를 USB로 연결하고 "이 컴퓨터 신뢰" → 기기에서 설정 › 개인정보 보호 및 보안 ›
   개발자 모드를 켜고 재시동한다.
4. Xcode 상단에서 실행 대상으로 기기를 고르고 ⌘R. 처음에는 Xcode가 기기를 팀에 등록하고 프로비저닝
   프로파일을 만든다(자동 서명). 기기 iOS 버전용 지원 파일 다운로드를 요구하면 허용한다.
5. 앱 첫 실행 시 "로컬 네트워크" 권한을 허용한다(192.168.x.x LAN 접속에 필요).

시뮬레이터로 보려면 Xcode › Settings › Components에서 iOS 27.2 Simulator 런타임(수 GB)을 받아야 한다.

Mac 쪽: 시스템 설정 › 일반 › 공유 › 화면 공유가 켜져 있고, 접근 허용 목록에 로그인할 계정이 있어야 한다.

## 조작

| 동작 | 결과 |
| --- | --- |
| 한 손가락 이동 | 포인터 상대 이동(손을 떼고 다른 곳에서 이어도 현재 위치 기준) |
| 탭 / 두 번 탭 | 클릭 / 더블클릭 |
| 탭 후 다시 눌러 끌기 | 드래그 |
| 두 손가락 탭 | 오른쪽 클릭 |
| 두 손가락 드래그 | 스크롤(상하좌우·대각선) |
| 핀치 | 확대/축소(포인터 기준, 중앙 1/3 규칙 유지) |
| 도구모음 | 키보드 · 모니터(1/2/전체, 자동 전환, 포인터 가두기) · ⌃⌥⇧⌘ · 더보기 · 종료 |
| 더보기 | 텍스트 보내기(한글은 붙여넣기), Mac 단축키(⌃Space 입력 소스 등), 특수 키, 새로고침(복구용) |

Mac 잠금 화면이 보이면 키보드로 암호를 직접 입력해 해제한다(앱은 암호를 자동 입력하지 않는다).

## 검증 상태 (2026-11-01)

| 항목 | 상태 |
| --- | --- |
| 코어 로직 68개 테스트(중앙 1/3, 확대·회전·키보드 재계산, 가장자리 clamp, 2축 스크롤, 모니터 배치·음수 좌표·배율, 제스처, 프로필) | ✅ macOS `swift test` 통과 |
| 엔진 10개 테스트(세션 설정, 오류 분류, 닫힌 포트 → 네트워크 오류) | ✅ 통과 |
| iOS 시뮬레이터/실기기 SDK 컴파일 | ✅ (서명 없이) |
| 이 Mac 화면 공유 서버와 프로토콜·보안 협상·Apple 인증 교환 | ✅ 존재하지 않는 계정으로 시도 → "로그인 실패"로 정확히 분류 |
| 앱 UI(목록·편집·암호 시트) | ✅ Mac Catalyst 임시 빌드로 표시 확인 (시트 환경 누락 크래시 1건 발견·수정) |
| 실제 계정 로그인 → 연속 갱신 → 모니터 선택 (`Tools/run-probe.sh`, 127.0.0.1) | ✅ 인증·연결 0.63s, 첫 화면 0.44s(수동 Refresh 없음), 포인터 이동 중 3s 58회 갱신, 복구용 Refresh 동작, 모니터 2개(주 5120×2160 Retina + 3440×1440 위쪽 배치) 인식, 모니터 1/2/전체 선택·잘라낸 영역 일치 |
| 화면 내용 암호화 | ⚠️ Standard 모드에서 `none` — 인증 교환만 보호됨. NetBird(WireGuard)로는 터널이 암호화하지만 LAN 직접 접속은 화면·키 입력이 평문 |
| 아이폰/아이패드 실기기 동작(제스처 체감, 키보드, 외장 포인터, 회전·멀티태스킹) | ❌ 미검증 |
| 한글 입력(⌃Space 후 직접 입력, 붙여넣기) | ❌ 미검증 |

## 라이선스

ScreenMate 자체 코드의 라이선스는 아직 정하지 않았다. 포함된 서드파티 코드와 고지는
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
