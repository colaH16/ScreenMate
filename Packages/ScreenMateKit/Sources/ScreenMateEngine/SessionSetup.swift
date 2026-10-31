import Foundation
import RFBProtocol
import rootshellVNC
import ScreenMateCore

/// How ScreenMate talks to a Mac. Every choice here is a product decision,
/// so it lives in one place and is covered by tests.
public enum SessionSetup {
    /// Limited automatic reconnection after an established session drops.
    public static let reconnectionPolicy = VNCReconnectionPolicy(
        isEnabled: true,
        maximumAttempts: 5,
        initialDelay: 1,
        maximumDelay: 15)

    public static func configuration(for profile: ConnectionProfile) -> VNCConfiguration {
        VNCConfiguration(
            // Apple High Performance mode needs direct UDP; Standard works
            // over TCP through NetBird and keeps one rendering path.
            enableHighPerformanceMode: false,
            videoQualityMode: profile.quality.videoQualityMode,
            // Never ask the Mac to create virtual displays sized for the
            // phone: show its real monitors.
            displaySizingMode: .remoteDisplay,
            // Receive the combined desktop and pick monitors on the client,
            // so monitor 1, monitor 2 and "all" switch instantly.
            displayMode: .allDisplaysCombined,
            enableRemoteAudio: false,
            // VNC sign-in and unlocking the Mac's lock screen are separate.
            // The app never types the saved password into the Mac.
            promptForLoginPasswordAtLoginWindow: false,
            // Draw the pointer locally at the trackpad position, without a
            // network round trip.
            cursorRendering: .client,
            remoteSystem: .mac,
            targetFrameRate: 60,
            reconnectionPolicy: reconnectionPolicy,
            securityPolicy: .automatic)
    }

    public static func credentials(for profile: ConnectionProfile, password: String) -> VNCCredentials {
        VNCCredentials(
            host: profile.host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: UInt16(clamping: profile.port),
            password: password,
            username: profile.username.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension StreamQuality {
    var videoQualityMode: VNCConfiguration.VideoQualityMode {
        switch self {
        case .standard: .standard
        case .fullQuality: .fullQuality
        }
    }
}

extension ConnectionFailure {
    /// Sort engine errors into what the user can do about them. Returns nil
    /// for a cancelled attempt (the user closed the session).
    public static func classify(_ error: any Error) -> ConnectionFailure? {
        if error is CancellationError { return nil }
        if let vnc = error as? VNCError {
            switch vnc {
            case .connectionFailed(let detail):
                return ConnectionFailure(kind: .network, detail: detail)
            case .authenticationFailed(let detail):
                return ConnectionFailure(kind: .authentication, detail: detail)
            case .protocolError(let underlying):
                return classify(protocolError: underlying)
            case .unsupportedFeature(let detail):
                return ConnectionFailure(kind: .unsupported, detail: detail)
            case .framebufferError(let detail):
                return ConnectionFailure(kind: .protocolError, detail: detail)
            case .notConnected, .alreadyConnected:
                return ConnectionFailure(kind: .protocolError, detail: vnc.localizedDescription)
            }
        }
        if let protocolError = error as? VNCProtocolError {
            return classify(protocolError: protocolError)
        }
        return ConnectionFailure(kind: .network, detail: error.localizedDescription)
    }

    public static func classify(protocolError: VNCProtocolError) -> ConnectionFailure {
        let detail = protocolError.localizedDescription
        switch protocolError {
        case .authenticationFailed:
            return ConnectionFailure(kind: .authentication, detail: detail)
        case .connectionClosed, .timeout, .ioError:
            return ConnectionFailure(kind: .network, detail: detail)
        case .unsupportedVersion, .unsupportedEncoding:
            return ConnectionFailure(kind: .unsupported, detail: detail)
        case .unexpectedMessage, .protocolViolation:
            return ConnectionFailure(kind: .protocolError, detail: detail)
        }
    }
}
