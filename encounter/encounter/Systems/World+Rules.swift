//
//  World+Rules.swift
//  encounter
//

import Foundation

extension World {
    /// What the world's rule system has. Screens ask this rather than naming a system.
    var rules: RuleModules { RuleSystems.system(for: system).modules }
}
