import CoreGraphics
import Foundation
import RFBProtocol
import rootshellVNC
import Testing
@testable import ScreenMateCore
@testable import ScreenMateEngine

@Suite("Session setup")
struct SessionSetupTests {
    let profile = ConnectionProfile(name: "Mac mini", host: " 192.0.2.10 ", username: " user ")

    @Test func configurationMatchesConfirmedBehavior() {
        let config = SessionSetup.configuration(for: profile)
        #expect(config.videoQualityMode == .standard)
        #expect(config.displayMode == .allDisplaysCombined)
        #expect(config.displaySizingMode == .remoteDisplay)
        #expect(config.promptForLoginPasswordAtLoginWindow == false)
        #expect(config.cursorRendering == .client)
        #expect(config.enableRemoteAudio == false)
        #expect(config.securityPolicy == .automatic)
        #expect(config.reconnectionPolicy.isEnabled)
        #expect(config.reconnectionPolicy.maximumAttempts == 5)
        #expect(config.reconnectionPolicy.maximumDelay == 15)
    }

    @Test func fullQualityProfile() {
        var p = profile
        p.quality = .fullQuality
        #expect(SessionSetup.configuration(for: p).videoQualityMode == .fullQuality)
    }

    @Test func credentialsAreTrimmedAndCarryUsername() {
        let credentials = SessionSetup.credentials(for: profile, password: "pw")
        #expect(credentials.host == "192.0.2.10")
        #expect(credentials.port == 5900)
        #expect(credentials.username == "user")
        #expect(credentials.password == "pw")
    }
}

/// Confirmed behavior 1: connection, authentication and protocol errors are
/// reported separately.
@Suite("Failure classification")
struct FailureClassificationTests {
    @Test func engineErrorsMapToActionableKinds() {
        #expect(ConnectionFailure.classify(VNCError.connectionFailed("refused"))?.kind == .network)
        #expect(ConnectionFailure.classify(VNCError.authenticationFailed("bad"))?.kind == .authentication)
        #expect(ConnectionFailure.classify(VNCError.unsupportedFeature("x"))?.kind == .unsupported)
        #expect(ConnectionFailure.classify(VNCError.protocolError(.protocolViolation("x")))?.kind == .protocolError)
        #expect(ConnectionFailure.classify(VNCError.protocolError(.timeout))?.kind == .network)
        #expect(ConnectionFailure.classify(VNCError.protocolError(.authenticationFailed("x")))?.kind == .authentication)
        #expect(ConnectionFailure.classify(protocolError: .unsupportedVersion).kind == .unsupported)
        #expect(ConnectionFailure.classify(URLError(.notConnectedToInternet))?.kind == .network)
    }

    @Test func cancellationIsNotAFailure() {
        #expect(ConnectionFailure.classify(CancellationError()) == nil)
    }

    @Test func detailIsKept() {
        #expect(ConnectionFailure.classify(VNCError.connectionFailed("Connection refused"))?.detail == "Connection refused")
    }
}

@Suite("Session controller without a connection")
@MainActor
struct RemoteSessionControllerTests {
    @Test func startsIdleWithRememberedMonitorAndDefaults() {
        var p = ConnectionProfile(name: "Mac", host: "h", username: "u")
        p.lastSelection = .monitor(2)
        let c = RemoteSessionController(profile: p)
        #expect(c.status == .idle)
        #expect(c.selection == .monitor(2))
        #expect(c.behavior.followsCursor == false)
        #expect(c.canRetryWithoutPassword == false)
    }

    @Test func modifierToggles() {
        let c = RemoteSessionController(profile: ConnectionProfile(name: "Mac", host: "h", username: "u"))
        c.toggleModifier(.command)
        c.toggleModifier(.shift)
        #expect(c.pendingModifiers == [.command, .shift])
        c.toggleModifier(.command)
        #expect(c.pendingModifiers == [.shift])
    }

    @Test func inputWhileDisconnectedIsHarmless() {
        let c = RemoteSessionController(profile: ConnectionProfile(name: "Mac", host: "h", username: "u"))
        c.movePointer(viewDelta: CGPoint(x: 10, y: 10), speed: 10)
        c.click(.left)
        c.scrollBegan()
        c.scrollChanged(viewDelta: CGPoint(x: 0, y: 30))
        c.scrollEnded()
        c.type("abc")
        c.paste("한글")
        c.hardwareKey(usage: 0x04, characters: "a", down: true)
        c.hardwareKey(usage: 0x04, characters: "a", down: false)
        c.refresh()
        c.releaseEverything()
        #expect(c.status == .idle)
    }

    @Test func connectionRefusedIsReportedAsNetworkFailure() async throws {
        // Port 1 on loopback is closed on any normal Mac.
        let c = RemoteSessionController(profile: ConnectionProfile(name: "Closed", host: "127.0.0.1", port: 1, username: "nobody"))
        await c.connect(password: "unused")
        guard case .failed(let failure) = c.status else {
            Issue.record("expected failure, got \(c.status)")
            return
        }
        #expect(failure.kind == .network)
        // A network failure keeps the typed password for a manual retry.
        #expect(c.canRetryWithoutPassword)
    }
}
