import Foundation

/// Picture transport offered to the Mac.
public enum StreamQuality: String, Codable, CaseIterable, Sendable {
    /// Apple Standard mode, adaptive quality over TCP. Works through NetBird
    /// and other tunnels; the default.
    case standard
    /// Apple Standard mode, lossless. Best on a fast local network.
    case fullQuality
}

/// A saved Mac. The password is never part of this value; it lives in the
/// Keychain under `id` when `savesPassword` is on.
public struct ConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var savesPassword: Bool
    public var quality: StreamQuality
    public var monitorBehavior: MonitorBehavior
    public var lastSelection: DisplaySelection
    public var lastConnectedAt: Date?

    public static let defaultPort = 5900

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = ConnectionProfile.defaultPort,
        username: String,
        savesPassword: Bool = false,
        quality: StreamQuality = .standard,
        monitorBehavior: MonitorBehavior = .default,
        lastSelection: DisplaySelection = .monitor(1),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.savesPassword = savesPassword
        self.quality = quality
        self.monitorBehavior = monitorBehavior
        self.lastSelection = lastSelection
        self.lastConnectedAt = lastConnectedAt
    }

    public var displayAddress: String {
        let bracketed = host.contains(":") ? "[\(host)]" : host
        return port == Self.defaultPort ? bracketed : "\(bracketed):\(port)"
    }

    /// One entry of the starter-profile JSON: the Macs offered on first
    /// launch. The real list lives in a git-ignored file next to the app
    /// sources so personal addresses never reach the repository.
    struct Starter: Decodable {
        var name: String
        var host: String
        var port: Int?
        var username: String
    }

    /// Profiles offered on first launch, from
    /// `[{"name", "host", "port"?, "username"}]`. Every field stays editable.
    public static func starterProfiles(json: Data) throws -> [ConnectionProfile] {
        try JSONDecoder().decode([Starter].self, from: json).map {
            ConnectionProfile(name: $0.name, host: $0.host, port: $0.port ?? defaultPort, username: $0.username)
        }
    }
}

/// Parses what people type into the address field: `host`, `host:port`,
/// `[v6]:port`, bare IPv6, and `vnc://user@host:port` URLs.
public struct HostInput: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var username: String?

    public init(host: String, port: Int? = nil, username: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
    }

    public static func parse(_ raw: String) -> HostInput {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["vnc://", "rfb://"] where text.lowercased().hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        var username: String?
        if let at = text.lastIndex(of: "@") {
            let user = String(text[..<at])
            username = user.isEmpty ? nil : (user.removingPercentEncoding ?? user)
            text = String(text[text.index(after: at)...])
        }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            let port = rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil
            return HostInput(host: host, port: port, username: username)
        }
        let colons = text.filter { $0 == ":" }.count
        if colons == 1, let colon = text.firstIndex(of: ":") {
            let host = String(text[..<colon])
            let port = Int(text[text.index(after: colon)...])
            return HostInput(host: host, port: port, username: username)
        }
        // Zero colons, or a bare IPv6 address.
        return HostInput(host: text, port: nil, username: username)
    }
}

public enum ProfileIssue: Equatable, Sendable {
    case emptyName
    case emptyHost
    case invalidHost
    case invalidPort
    case emptyUsername

    public var message: String {
        switch self {
        case .emptyName: "이름을 입력하세요."
        case .emptyHost: "주소 또는 호스트 이름을 입력하세요."
        case .invalidHost: "주소에 공백이나 사용할 수 없는 문자가 있습니다."
        case .invalidPort: "포트는 1–65535 사이여야 합니다."
        case .emptyUsername: "Mac 사용자 이름을 입력하세요. Mac 화면 공유는 계정 인증을 사용합니다."
        }
    }
}

extension ConnectionProfile {
    public var issues: [ProfileIssue] {
        var issues: [ProfileIssue] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyName) }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        if trimmedHost.isEmpty {
            issues.append(.emptyHost)
        } else if trimmedHost.contains(where: { $0.isWhitespace || "/@[]".contains($0) }) {
            issues.append(.invalidHost)
        }
        if !(1...65535).contains(port) { issues.append(.invalidPort) }
        if username.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyUsername) }
        return issues
    }

    public var isValid: Bool { issues.isEmpty }
}
