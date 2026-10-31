import Foundation
import Testing
@testable import ScreenMateCore

/// Confirmed behavior 1: saved Macs with name, address, port, user name.
@Suite("Connection profiles")
struct ProfileTests {
    @Test func hostInputParsing() {
        #expect(HostInput.parse(" 192.0.2.10 ") == HostInput(host: "192.0.2.10"))
        #expect(HostInput.parse("192.0.2.10:5901") == HostInput(host: "192.0.2.10", port: 5901))
        #expect(HostInput.parse("vnc://user@mac-mini.example.net:5900") ==
                HostInput(host: "mac-mini.example.net", port: 5900, username: "user"))
        #expect(HostInput.parse("[fe80::1]:5900") == HostInput(host: "fe80::1", port: 5900))
        #expect(HostInput.parse("fe80::1") == HostInput(host: "fe80::1"))
        #expect(HostInput.parse("vnc://mac.local/") == HostInput(host: "mac.local"))
    }

    @Test func validation() {
        var p = ConnectionProfile(name: "Mac mini", host: "192.0.2.10", username: "user")
        #expect(p.isValid)
        p.port = 0
        #expect(p.issues == [.invalidPort])
        p.port = 5900
        p.username = " "
        #expect(p.issues == [.emptyUsername])
        p.username = "user"
        p.host = "my mac"
        #expect(p.issues == [.invalidHost])
        p.host = ""
        p.name = ""
        #expect(p.issues == [.emptyName, .emptyHost])
    }

    @Test func displayAddressHidesDefaultPort() {
        #expect(ConnectionProfile(name: "a", host: "h", username: "u").displayAddress == "h")
        #expect(ConnectionProfile(name: "a", host: "h", port: 5901, username: "u").displayAddress == "h:5901")
        #expect(ConnectionProfile(name: "a", host: "fe80::1", username: "u").displayAddress == "[fe80::1]")
    }

    @Test func starterProfilesComeFromJSON() throws {
        let json = Data("""
        [
          { "name": "Mac mini (LAN)", "host": "192.0.2.10", "port": 5900, "username": "user" },
          { "name": "Mac mini (VPN)", "host": "mac-mini.example.net", "username": "user" }
        ]
        """.utf8)
        let starters = try ConnectionProfile.starterProfiles(json: json)
        #expect(starters.map(\.host) == ["192.0.2.10", "mac-mini.example.net"])
        #expect(starters.allSatisfy { $0.port == 5900 && $0.username == "user" && $0.isValid })
        #expect(starters.allSatisfy { !$0.savesPassword && $0.monitorBehavior == .default })
        #expect(throws: (any Error).self) { try ConnectionProfile.starterProfiles(json: Data("{}".utf8)) }
    }

    @Test func exampleStarterFileParses() throws {
        // docs/StarterProfiles.example.json documents the git-ignored file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/StarterProfiles.example.json")
        let starters = try ConnectionProfile.starterProfiles(json: Data(contentsOf: url))
        #expect(starters.count == 2)
    }

    @Test func fileRoundTripStoresNoPassword() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = ProfileFile(url: dir.appendingPathComponent("profiles.json"))
        #expect(try file.load() == nil)
        var profile = ConnectionProfile(name: "Mac mini", host: "192.0.2.10", username: "user", savesPassword: true)
        profile.lastSelection = .monitor(2)
        profile.monitorBehavior = MonitorBehavior(followsCursor: true, confinesCursorToSelectedMonitor: false)
        profile.lastConnectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try file.save([profile])
        #expect(try file.load() == [profile])
        let json = try String(contentsOf: file.url, encoding: .utf8)
        #expect(!json.contains("\"password\""))
        #expect(json.contains("\"savesPassword\" : true"))
    }

    @Test func passwordStoreContract() throws {
        let store = InMemoryPasswordStore()
        let id = UUID()
        #expect(try store.password(for: id) == nil)
        try store.setPassword("secret", for: id)
        #expect(try store.password(for: id) == "secret")
        try store.removePassword(for: id)
        #expect(try store.password(for: id) == nil)
    }

    @Test func failureMessagesDistinguishKinds() {
        let kinds: [ConnectionFailureKind] = [.network, .authentication, .protocolError, .unsupported]
        let titles = Set(kinds.map { ConnectionFailure(kind: $0, detail: "").title })
        #expect(titles.count == kinds.count)
    }
}
