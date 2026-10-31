import Foundation
import Observation
import ScreenMateCore
import ScreenMateEngine

/// An open session shown full screen.
@MainActor
struct ActiveSession: Identifiable {
    let id = UUID()
    let controller: RemoteSessionController
}

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ConnectionProfile] = []
    var activeSession: ActiveSession?
    var storageError: String?

    @ObservationIgnored private let file: ProfileFile?
    @ObservationIgnored private let passwords: any PasswordStore

    init(passwords: any PasswordStore = KeychainPasswordStore()) {
        self.passwords = passwords
        self.file = try? ProfileFile.standard()
        do {
            if let saved = try file?.load() {
                profiles = saved
            } else {
                profiles = Self.bundledStarterProfiles()
                persist()
            }
        } catch {
            profiles = Self.bundledStarterProfiles()
            storageError = "저장된 접속 목록을 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// First-launch Macs from `App/StarterProfiles.json`. That file is
    /// git-ignored (it holds personal addresses); without it the list starts
    /// empty. Format: `docs/StarterProfiles.example.json`.
    private static func bundledStarterProfiles() -> [ConnectionProfile] {
        guard let url = Bundle.main.url(forResource: "StarterProfiles", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? ConnectionProfile.starterProfiles(json: data)) ?? []
    }

    var sortedProfiles: [ConnectionProfile] {
        profiles.sorted {
            switch ($0.lastConnectedAt, $1.lastConnectedAt) {
            case let (a?, b?): a > b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Profiles

    /// Save a profile. `password` replaces the stored one when non-nil and
    /// `savesPassword` is on; turning `savesPassword` off deletes it.
    func save(_ profile: ConnectionProfile, password: String?) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        if profile.savesPassword {
            if let password, !password.isEmpty {
                do {
                    try passwords.setPassword(password, for: profile.id)
                } catch {
                    storageError = "Keychain에 암호를 저장하지 못했습니다. 다음 연결 때 암호를 다시 묻습니다."
                }
            }
        } else {
            // Best effort: nothing to report when there was nothing saved.
            try? passwords.removePassword(for: profile.id)
        }
        persist()
    }

    func delete(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? passwords.removePassword(for: profile.id)
        persist()
    }

    func hasSavedPassword(_ profile: ConnectionProfile) -> Bool {
        profile.savesPassword && ((try? passwords.password(for: profile.id)) ?? nil) != nil
    }

    private func persist() {
        do {
            try file?.save(profiles)
        } catch {
            storageError = "접속 목록을 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - Sessions

    /// Connect with the Keychain password when one is saved. Returns false
    /// when the caller must ask for the password.
    func connectWithSavedPassword(_ profile: ConnectionProfile) -> Bool {
        guard profile.savesPassword,
              let password = (try? passwords.password(for: profile.id)) ?? nil else { return false }
        start(profile, password: password)
        return true
    }

    func connect(_ profile: ConnectionProfile, password: String, remember: Bool) {
        var updated = profile
        updated.savesPassword = remember
        save(updated, password: remember ? password : nil)
        start(updated, password: password)
    }

    private func start(_ profile: ConnectionProfile, password: String) {
        let controller = RemoteSessionController(profile: profile)
        controller.onProfileChange = { [weak self] changed in
            self?.updateFromSession(changed)
        }
        activeSession = ActiveSession(controller: controller)
        Task { await controller.connect(password: password) }
    }

    /// Remember monitor choice and connection time without touching the
    /// password.
    private func updateFromSession(_ changed: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == changed.id }) else { return }
        var stored = profiles[index]
        stored.lastSelection = changed.lastSelection
        stored.monitorBehavior = changed.monitorBehavior
        stored.lastConnectedAt = changed.lastConnectedAt
        guard stored != profiles[index] else { return }
        profiles[index] = stored
        persist()
    }

    func endSession() {
        activeSession?.controller.disconnect()
        activeSession = nil
    }
}
