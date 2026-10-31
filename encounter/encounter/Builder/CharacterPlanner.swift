//
//  CharacterPlanner.swift
//  encounter
//

import Foundation

/// Points at a race, class or background: an entry of the library, or a page of the world.
nonisolated enum ContentChoice: Hashable, Sendable {
    case library(String)
    case page(UUID)
}

/// A race, class or background as the builder reads it. A library entry and a world page that was made from one have
/// the same keys, so both are read the same way.
nonisolated struct ContentSource: Sendable, Identifiable, Hashable {
    var choice: ContentChoice
    var name: String
    var summary = ""
    var attributes: [String: AttributeValue] = [:]
    var entries: [EntryValue] = []
    /// The library entry this is, or was made from, which a class needs to find its spell list and subclasses.
    var libraryKey: String?

    var id: ContentChoice { choice }

    /// Where this comes from: the library's pack for the edition, such as "SRD 5.2.1", or the world's own pages.
    var sourceTitle: String {
        guard let key = libraryKey ?? { if case .library(let key) = choice { key } else { nil } }(),
              case .library = choice,
              let edition = LibraryEdition(key: key),
              let pack = Library.shared.pack(for: edition)
        else { return String(localized: "This World") }
        return pack.name
    }

    func text(_ key: String) -> String? {
        if case .text(let value)? = attributes[key], !value.isEmpty { value } else { nil }
    }

    /// The text of the trait or feature with this name, if it has one.
    func entryText(named name: String) -> String? {
        entries.first { $0.name == name }?.text
    }

    static func == (lhs: ContentSource, rhs: ContentSource) -> Bool { lhs.choice == rhs.choice }
    func hash(into hasher: inout Hasher) { hasher.combine(choice) }
}

/// How a character's ability scores are set before bonuses.
nonisolated enum ScoreMethod: String, CaseIterable, Identifiable, Sendable {
    case standardArray
    case pointBuy
    case manual

    var id: String { rawValue }
}

/// A background's ability score bonus in the 2024 rules: +2 and +1 to two of its three abilities, or +1 to all three.
nonisolated enum BackgroundBonus: Equatable, Sendable {
    case twoAndOne(two: Ability, one: Ability)
    case oneEach
}

/// Everything the creator chooses while building a level 1 character.
nonisolated struct CharacterDraft: Sendable {
    var name = ""
    var alignment = ""
    var race: ContentChoice?
    /// A subrace, in the 2014 rules: the key of a library entry whose parent is the race.
    var subrace: String?
    var characterClass: ContentChoice?
    var subclass: String?
    var background: ContentChoice?

    var method = ScoreMethod.standardArray
    var scores: [Ability: Int] = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })
    /// Abilities chosen for a race's "of your choice" bonuses (2014).
    var raceBonusChoices: [Ability] = []
    var backgroundBonus: BackgroundBonus?

    var skills: Set<String> = []
    /// For each group of starting equipment, the option chosen: a class's groups, then the background's.
    var equipmentChoices: [Int: Int] = [:]
    var cantrips: Set<String> = []
    var spells: Set<String> = []
}

/// What the draft comes to: the scores and the values worked out from them, and what is still missing.
nonisolated struct CharacterPlan: Sendable {
    var scores: [Ability: Int] = [:]
    var bonuses: [Ability: Int] = [:]
    var hitPoints: Int?
    var hitDie: String?
    var armorClass: Int?
    var proficiencyBonus = CharacterRules.level1ProficiencyBonus
    var savingThrows: [String] = []
    var backgroundSkills: [String] = []
    var classSkillChoice: SkillChoice?
    var skills: [String] = []
    var equipmentGroups: [EquipmentGroup] = []
    var equipment: [String] = []
    var spellLimits = SpellLimits()
    var cantripLimit = 0
    var spellLimit: Int?
    /// What stops the character being created.
    var problems: [String] = []
    /// What the builder couldn't read from the rules text, which the creator fills in on the page.
    var notes: [String] = []
}

nonisolated enum CharacterPlanner {
    /// Works out a plan for the draft.
    /// - Parameters:
    ///   - edition: Decides where ability bonuses come from: the race in the 2014 rules, the background in the 2024 rules.
    static func plan(
        _ draft: CharacterDraft,
        edition: LibraryEdition,
        race: ContentSource?,
        characterClass: ContentSource?,
        background: ContentSource?
    ) -> CharacterPlan {
        var plan = CharacterPlan()

        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { plan.problems.append("Give the character a name.") }
        if race == nil { plan.problems.append("Choose a race or species.") }
        if characterClass == nil { plan.problems.append("Choose a class.") }
        if background == nil { plan.problems.append("Choose a background.") }

        // Ability scores: the base scores, then the bonuses.
        switch draft.method {
        case .standardArray:
            if draft.scores.values.sorted(by: >) != CharacterRules.standardArray { plan.problems.append("Use each number of the standard array once.") }
        case .pointBuy:
            if let total = CharacterRules.pointBuyTotal(of: Array(draft.scores.values)) {
                if total > CharacterRules.pointBuyBudget { plan.problems.append("Point buy is over its \(CharacterRules.pointBuyBudget) points.") }
            } else {
                plan.problems.append("Point buy scores go from 8 to 15.")
            }
        case .manual:
            if draft.scores.values.contains(where: { !(1...CharacterRules.maximumScore).contains($0) }) { plan.problems.append("Scores go from 1 to 20.") }
        }

        var bonuses: [Ability: Int] = [:]
        if edition == .srd51 {
            if let race {
                let text = race.entryText(named: "Ability Score Increase") ?? ""
                let parsed = AbilityBonuses.parse(text)
                if parsed.isUnderstood {
                    for (ability, amount) in parsed.fixed { bonuses[ability, default: 0] += amount }
                    if let choices = parsed.choices {
                        let picked = draft.raceBonusChoices.filter { parsed.fixed[$0] == nil }
                        if Set(picked).count != choices.count { plan.problems.append("Choose \(choices.count) abilities for the race’s bonus.") }
                        for ability in Set(picked) { bonuses[ability, default: 0] += choices.amount }
                    }
                } else {
                    plan.notes.append("The race’s ability score increase couldn’t be read (“\(text)”). Add it to the scores on the page.")
                }
            }
        } else if let background {
            let abilities = SkillList.parse(background.text("dnd5e.backgroundAbilityScores") ?? "").compactMap { Ability(name: $0) }
            switch draft.backgroundBonus {
            case .twoAndOne(let two, let one)?:
                if two == one || !abilities.contains(two) || !abilities.contains(one) { plan.problems.append("Choose two different abilities the background offers.") }
                else { bonuses[two, default: 0] += 2; bonuses[one, default: 0] += 1 }
            case .oneEach?:
                for ability in abilities { bonuses[ability, default: 0] += 1 }
                if abilities.isEmpty { plan.notes.append("The background’s ability scores couldn’t be read. Add them on the page.") }
            case nil:
                plan.problems.append("Choose how the background raises your ability scores.")
            }
        }
        var scores: [Ability: Int] = [:]
        for ability in Ability.allCases { scores[ability] = min(CharacterRules.maximumScore, (draft.scores[ability] ?? 10) + (bonuses[ability] ?? 0)) }
        plan.scores = scores
        plan.bonuses = bonuses

        // The class: hit die, saving throws, skills, equipment, spells.
        if let characterClass {
            if let die = characterClass.text("dnd5e.hitDie"), let sides = CharacterRules.hitDieSides(die) {
                plan.hitDie = "d\(sides)"
                plan.hitPoints = CharacterRules.hitPointsAtLevel1(hitDie: sides, constitution: scores[.constitution] ?? 10)
            } else {
                plan.notes.append("The class has no hit die, so hit points were left blank.")
            }
            plan.savingThrows = SkillList.parse(characterClass.text("dnd5e.savingThrows") ?? "")
            plan.classSkillChoice = SkillChoice.parse(characterClass.text("dnd5e.skillChoices") ?? "")
            if plan.classSkillChoice == nil { plan.notes.append("The class’s skill choices couldn’t be read. Add skills on the page.") }
            plan.equipmentGroups = EquipmentGroup.parse(characterClass.text("dnd5e.startingEquipment") ?? "")

            let casting = characterClass.entries.first { $0.level == 1 && ($0.name == "Spellcasting" || $0.name == "Pact Magic") }
            plan.spellLimits = casting.map { SpellLimits.parse($0.text) } ?? SpellLimits()
        }
        plan.armorClass = CharacterRules.unarmoredArmorClass(dexterity: scores[.dexterity] ?? 10)

        // Skills: the background's, and the class's choices from those left.
        if let background {
            plan.backgroundSkills = SkillList.parse(background.text("dnd5e.backgroundSkills") ?? "")
            plan.equipmentGroups += EquipmentGroup.parse(background.text("dnd5e.backgroundEquipment") ?? "")
        }
        let classPicks = draft.skills.subtracting(plan.backgroundSkills)
        if let choice = plan.classSkillChoice {
            if classPicks.count != choice.count { plan.problems.append("Choose \(choice.count) class skills.") }
            if !classPicks.isSubset(of: Set(choice.options)) { plan.problems.append("A chosen skill isn’t on the class’s list.") }
        }
        plan.skills = (plan.backgroundSkills + classPicks.sorted()).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        // Equipment: fixed groups as they are, choices as picked.
        for (index, group) in plan.equipmentGroups.enumerated() {
            if group.isChoice {
                if let pick = draft.equipmentChoices[index], group.options.indices.contains(pick) { plan.equipment += EquipmentGroup.items(in: group.options[pick].text) }
                else { plan.problems.append("Choose your starting equipment.") }
            } else if let only = group.options.first {
                plan.equipment += EquipmentGroup.items(in: only.text)
            }
        }
        plan.problems = plan.problems.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        // Spells: how many cantrips and spells the class chooses.
        let limits = plan.spellLimits
        plan.cantripLimit = limits.cantrips
        switch limits.spells {
        case .fixed(let n): plan.spellLimit = n
        case .abilityPlusLevel(let ability): plan.spellLimit = max(1, 1 + CharacterRules.modifier(for: scores[ability] ?? 10))
        case .none: plan.spellLimit = nil
        }
        if draft.cantrips.count > limits.cantrips { plan.problems.append("Too many cantrips: this class knows \(limits.cantrips).") }
        if let limit = plan.spellLimit, draft.spells.count > limit { plan.problems.append("Too many spells: this class has \(limit).") }
        if limits.isCaster, draft.cantrips.count < limits.cantrips || (plan.spellLimit.map { draft.spells.count < $0 } ?? false) {
            plan.notes.append("Not all of the class’s cantrips and spells are chosen yet.")
        }
        return plan
    }
}
