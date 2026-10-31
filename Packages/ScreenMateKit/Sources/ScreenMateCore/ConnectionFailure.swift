import Foundation

/// Why a connection did not come up, in categories the user can act on.
public enum ConnectionFailureKind: String, Equatable, Sendable {
    /// The Mac could not be reached (address, port, network, NetBird).
    case network
    /// The Mac rejected the account name or password.
    case authentication
    /// The Mac answered but the conversation broke down.
    case protocolError
    /// The Mac asked for something this app does not support.
    case unsupported
}

public struct ConnectionFailure: Error, Equatable, Sendable {
    public let kind: ConnectionFailureKind
    /// Technical detail from the engine, shown small under the summary.
    public let detail: String

    public init(kind: ConnectionFailureKind, detail: String) {
        self.kind = kind
        self.detail = detail
    }

    public var title: String {
        switch kind {
        case .network: "Mac에 연결할 수 없음"
        case .authentication: "로그인 실패"
        case .protocolError: "화면 공유 통신 오류"
        case .unsupported: "지원하지 않는 화면 공유 설정"
        }
    }

    public var suggestion: String {
        switch kind {
        case .network:
            "주소와 포트(기본 5900), 같은 네트워크 또는 NetBird 연결, Mac의 '화면 공유' 켜짐 여부를 확인하세요."
        case .authentication:
            "Mac 로그인 계정의 사용자 이름과 암호를 확인하세요. 화면 공유 '접근 허용' 목록에 계정이 있어야 합니다."
        case .protocolError:
            "다시 연결해 보세요. 반복되면 Mac에서 화면 공유를 껐다 켜세요."
        case .unsupported:
            "Mac의 시스템 설정 > 일반 > 공유 > 화면 공유가 켜져 있는지 확인하세요. Windows·Linux VNC 서버는 지원하지 않습니다."
        }
    }
}
