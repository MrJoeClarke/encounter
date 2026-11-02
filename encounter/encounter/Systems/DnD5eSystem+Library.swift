//
//  DnD5eSystem+Library.swift
//  encounter
//

import Foundation

extension DnD5eSystem {
    var libraryAttributeLabels: [String: String] { ["dnd5e.ability": "Ability"] }
    var scoreRange: ClosedRange<Int> { Self.abilityScoreRange }

    /// For a class, its hit die and primary ability; for a race or species, its size and speed; and so on for each kind.
    func libraryDetail(for entry: LibraryEntry) -> String? {
        if let line = entry.detail, !line.isEmpty { return line }
        func text(_ key: String) -> String? {
            if case .text(let value)? = entry.attributes[key], !value.isEmpty { value } else { nil }
        }
        let parts: [String?]
        switch entry.kind {
        case .class: parts = [text("dnd5e.hitDie").map { String(localized: "Hit die \($0)") }, text("dnd5e.primaryAbility")]
        case .race, .subclass: parts = [text("core.raceSize"), text("dnd5e.speed")]
        case .skill: parts = [text("dnd5e.ability")]
        case .condition, .entry: parts = []
        case .background: parts = [text("dnd5e.backgroundSkills")]
        case .feat: parts = [text("dnd5e.featCategory"), text("dnd5e.featPrerequisite")]
        case .equipment: parts = [text("dnd5e.equipmentCategory"), text("dnd5e.cost")]
        case .spell: parts = [entry.spellHeadline, text("dnd5e.spellClasses")]
        }
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}
