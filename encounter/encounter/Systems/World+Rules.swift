//
//  World+Rules.swift
//  encounter
//

import Foundation

extension World {
    /// What the world's rule system has. Screens ask this rather than naming a system.
    var rules: RuleModules { RuleSystems.system(forKey: systemRaw).modules }

    /// The system the world uses, by name, even one the app doesn't have.
    var systemTitle: String { RuleSystems.title(forKey: systemRaw) }

    /// Chooses a system by key and records its version.
    func choose(systemKey key: String) {
        systemRaw = key
        let system = RuleSystems.system(forKey: key)
        systemVersion = system.version
        // A system's library is its own, so the world moves to an edition the system has.
        let editions = system.libraryEditions
        if let first = editions.first, !editions.contains(edition) { edition = first }
    }

    /// How the system the world recorded compares with what the app has.
    var systemStatus: SystemStatus { RuleSystems.status(key: systemRaw, recordedVersion: systemVersion) }
}
