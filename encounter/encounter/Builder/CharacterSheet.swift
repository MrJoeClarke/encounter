//
//  CharacterSheet.swift
//  encounter
//

import Foundation
import SwiftData

/// How well a character knows a skill.
enum SkillProficiency: Equatable {
    case none
    /// Half the proficiency bonus, from Jack of All Trades.
    case half
    case proficient
    /// Twice the proficiency bonus.
    case expertise
}

/// A skill with the character's bonus in it.
struct SheetSkill: Identifiable, Equatable {
    var name: String
    var ability: Ability
    var proficiency: SkillProficiency
    var bonus: Int
    var id: String { name }

    var isProficient: Bool { proficiency == .proficient || proficiency == .expertise }
}

struct SheetSave: Identifiable, Equatable {
    var ability: Ability
    var isProficient: Bool
    var bonus: Int
    var id: Ability { ability }
}

/// A weapon the character carries, with what to roll to use it.
struct SheetAttack: Identifiable {
    var weapon: SheetRules.Weapon
    var ability: Ability
    var isProficient: Bool
    var attackBonus: Int
    /// The damage dice with the ability modifier added.
    var damage: DiceExpression
    var versatileDamage: DiceExpression?
    var id: String { weapon.name }
}

/// A spell the character has, found in the library where possible.
struct SheetSpell: Identifiable {
    var name: String
    var entry: LibraryEntry?
    var level: Int
    var id: String { entry?.key ?? name }
    var isRitual: Bool {
        if case .bool(true)? = entry?.attributes["dnd5e.ritual"] { true } else { false }
    }
}

/// The numbers on a playable D&D character's sheet, worked out from the character's page. Nothing here is stored
/// apart from what is played: current and temporary hit points, spent hit dice and used spell slots.
@MainActor
struct CharacterSheet {
    let page: Page
    let world: World

    let level: Int
    let proficiencyBonus: Int
    let scores: [Ability: Int]
    let className: String
    let progression: ClassProgression?

    init?(page: Page) {
        guard page.kind == .character, let world = page.world, world.system == .dnd5e else { return nil }
        self.page = page
        self.world = world
        level = max(1, min(20, Int(page.attributeNumber("dnd5e.classLevel") ?? 1)))
        proficiencyBonus = Int(page.attributeNumber("dnd5e.proficiencyBonus") ?? Double(CharacterRules.proficiencyBonus(atLevel: level)))
        scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, Int(page.attributeNumber($0.attributeKey) ?? 10)) })
        let classSource = Self.reference(page, role: LinkRole.characterClass, in: world)
        className = classSource?.name ?? ""
        progression = classSource.flatMap { ClassProgression(attributes: $0.attributes) }
        classAttributes = classSource?.attributes ?? [:]
        // A custom class made from a library class keeps its name for finding the spellcasting ability.
        baseClassName = classSource?.libraryKey.flatMap { Library.shared.entry(forKey: $0)?.name } ?? classSource?.name ?? ""
    }

    private let classAttributes: [String: AttributeValue]
    private let baseClassName: String

    private static func reference(_ page: Page, role: String, in world: World) -> ContentSource? {
        switch page.reference(role: role) {
        case .library(let key): CharacterContent.resolve(.library(key), in: world)
        case .page(let target): CharacterContent.resolve(.page(target.id), in: world)
        case .none: nil
        }
    }

    func modifier(_ ability: Ability) -> Int { CharacterRules.modifier(for: scores[ability] ?? 10) }

    // MARK: Header

    var name: String { page.title.isEmpty ? String(localized: "Untitled") : page.title }

    var subtitle: String {
        var parts: [String] = []
        if let race = Self.reference(page, role: LinkRole.race, in: world)?.name { parts.append(race) }
        var classText = className
        if let key = page.libraryKey(role: "subclass"), let subclass = Library.shared.entry(forKey: key) { classText += " (\(subclass.name))" }
        if !classText.isEmpty { parts.append(classText + " \(level)") }
        if let background = Self.reference(page, role: LinkRole.background, in: world)?.name { parts.append(background) }
        return parts.joined(separator: " · ")
    }

    // MARK: Checks

    private func proficiencies(_ key: String) -> [String] {
        page.attributeText(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var saves: [SheetSave] {
        let proficient = Set(proficiencies("dnd5e.savingThrowProficiencies").map { $0.lowercased() })
        return Ability.allCases.map { ability in
            let isProficient = proficient.contains(ability.rawValue.lowercased())
            return SheetSave(ability: ability, isProficient: isProficient, bonus: modifier(ability) + (isProficient ? proficiencyBonus : 0))
        }
    }

    /// Whether the character has Jack of All Trades, which adds half the proficiency bonus to checks they aren't
    /// proficient in.
    var hasJackOfAllTrades: Bool {
        if case .entries(let features)? = page.attributes["dnd5e.classFeatures"] { features.contains { $0.name == "Jack of All Trades" } } else { false }
    }

    var halfProficiency: Int { hasJackOfAllTrades ? proficiencyBonus / 2 : 0 }

    var skills: [SheetSkill] {
        let proficient = Set(proficiencies("dnd5e.skillProficiencies").map { $0.lowercased() })
        let expert = Set(proficiencies("dnd5e.skillExpertise").map { $0.lowercased() })
        return Library.shared.entries(.skill, in: world.edition).compactMap { entry -> SheetSkill? in
            guard case .text(let abilityName)? = entry.attributes["dnd5e.ability"], let ability = Ability(name: abilityName) else { return nil }
            let key = entry.name.lowercased()
            let level: SkillProficiency = proficient.contains(key) ? (expert.contains(key) ? .expertise : .proficient) : (hasJackOfAllTrades ? .half : .none)
            let added: Int
            switch level {
            case .none: added = 0
            case .half: added = halfProficiency
            case .proficient: added = proficiencyBonus
            case .expertise: added = proficiencyBonus * 2
            }
            return SheetSkill(name: entry.name, ability: ability, proficiency: level, bonus: modifier(ability) + added)
        }
        // The library lists them by ability; a sheet lists them by name.
        .sorted { $0.name < $1.name }
    }

    /// Makes a skill (or its saving throw) proficient or not, on the character's page.
    func setSkill(_ name: String, proficient: Bool) { setSkill(name, to: proficient ? .proficient : .none) }

    /// Sets how well a skill is known. Expertise needs proficiency, so removing one removes the other.
    func setSkill(_ name: String, to level: SkillProficiency) {
        setProficiency("dnd5e.skillProficiencies", name, level == .proficient || level == .expertise)
        setProficiency("dnd5e.skillExpertise", name, level == .expertise)
    }

    func setSave(_ ability: Ability, proficient: Bool) { setProficiency("dnd5e.savingThrowProficiencies", ability.rawValue, proficient) }

    private func setProficiency(_ key: String, _ name: String, _ isProficient: Bool) {
        var list = proficiencies(key).filter { $0.localizedCaseInsensitiveCompare(name) != .orderedSame }
        if isProficient { list.append(name) }
        page.setAttributeText(key, list.joined(separator: ", "))
    }

    var passivePerception: Int {
        10 + (skills.first { $0.name == "Perception" }?.bonus ?? modifier(.wisdom))
    }

    /// Initiative is a Dexterity check, so Jack of All Trades helps.
    var initiative: Int { modifier(.dexterity) + halfProficiency }
    var armorClass: Int? { page.attributeNumber("dnd5e.armorClass").map(Int.init) }
    var speed: String { page.attributeText("dnd5e.speed") }

    // MARK: Hit points and hit dice

    var maximumHitPoints: Int { Int(page.attributeNumber("dnd5e.hitPoints") ?? 0) }

    var currentHitPoints: Int {
        min(maximumHitPoints, max(0, Int(page.attributeNumber("dnd5e.currentHitPoints") ?? Double(maximumHitPoints))))
    }

    var temporaryHitPoints: Int { max(0, Int(page.attributeNumber("dnd5e.temporaryHitPoints") ?? 0)) }

    /// Damage comes off temporary hit points first. At 0 hit points it is a failed death save (and if the damage
    /// left over at 0 is as much as the maximum, the character dies outright).
    func takeDamage(_ amount: Int) {
        guard amount > 0 else { return }
        let wasAtZero = currentHitPoints == 0 && maximumHitPoints > 0
        let absorbed = min(temporaryHitPoints, amount)
        let remaining = amount - absorbed
        page.setAttributeNumber("dnd5e.temporaryHitPoints", Double(temporaryHitPoints - absorbed))
        let before = currentHitPoints
        page.setAttributeNumber("dnd5e.currentHitPoints", Double(max(0, before - remaining)))
        guard remaining > 0, maximumHitPoints > 0 else { return }
        if remaining - before >= maximumHitPoints {
            page.setAttributeNumber("dnd5e.deathSaveFailures", 3)
        } else if wasAtZero {
            // Damage ends being stable, and counts as a failure.
            if isStable { page.setAttributeNumber("dnd5e.deathSaveSuccesses", 0) }
            addDeathSave(success: false, count: 1)
        }
    }

    func heal(_ amount: Int) {
        guard amount > 0 else { return }
        if currentHitPoints == 0 { resetDeathSaves() }
        page.setAttributeNumber("dnd5e.currentHitPoints", Double(min(maximumHitPoints, currentHitPoints + amount)))
    }

    // MARK: Death saves

    var deathSaveSuccesses: Int { min(3, max(0, Int(page.attributeNumber("dnd5e.deathSaveSuccesses") ?? 0))) }
    var deathSaveFailures: Int { min(3, max(0, Int(page.attributeNumber("dnd5e.deathSaveFailures") ?? 0))) }

    /// At 0 hit points and needing death saves.
    var isDying: Bool { currentHitPoints == 0 && maximumHitPoints > 0 && !isDead && !isStable }
    var isStable: Bool { currentHitPoints == 0 && deathSaveSuccesses >= 3 && deathSaveFailures < 3 }
    var isDead: Bool { deathSaveFailures >= 3 }
    var isAtZero: Bool { currentHitPoints == 0 && maximumHitPoints > 0 }

    /// What a death saving throw came to.
    enum DeathSaveOutcome: Equatable {
        case success, failure
        /// A natural 20: one hit point back, and up again.
        case revived
        /// A natural 1: two failures.
        case doubleFailure
    }

    /// Records the d20 of a death saving throw (no modifiers): 10 or more succeeds, less fails, a 1 is two failures,
    /// and a 20 brings the character back with 1 hit point.
    @discardableResult
    func recordDeathSave(roll: Int) -> DeathSaveOutcome {
        if roll >= 20 {
            resetDeathSaves()
            page.setAttributeNumber("dnd5e.currentHitPoints", 1)
            return .revived
        }
        if roll <= 1 { addDeathSave(success: false, count: 2); return .doubleFailure }
        let success = roll >= 10
        addDeathSave(success: success, count: 1)
        return success ? .success : .failure
    }

    /// Sets the marks by hand, for a table that keeps count some other way.
    func setDeathSaves(successes: Int, failures: Int) {
        page.setAttributeNumber("dnd5e.deathSaveSuccesses", Double(min(3, max(0, successes))))
        page.setAttributeNumber("dnd5e.deathSaveFailures", Double(min(3, max(0, failures))))
    }

    private func addDeathSave(success: Bool, count: Int) {
        if success {
            page.setAttributeNumber("dnd5e.deathSaveSuccesses", Double(min(3, deathSaveSuccesses + count)))
        } else {
            page.setAttributeNumber("dnd5e.deathSaveFailures", Double(min(3, deathSaveFailures + count)))
        }
    }

    func resetDeathSaves() { setDeathSaves(successes: 0, failures: 0) }

    /// Temporary hit points don't add up: a new amount replaces the old only if it is higher.
    func gainTemporaryHitPoints(_ amount: Int) {
        page.setAttributeNumber("dnd5e.temporaryHitPoints", Double(max(temporaryHitPoints, amount)))
    }

    func setTemporaryHitPoints(_ amount: Int) {
        page.setAttributeNumber("dnd5e.temporaryHitPoints", Double(max(0, amount)))
    }

    var hitDieSides: Int? { progression?.hitDieSides ?? CharacterRules.hitDieSides(page.attributeText("dnd5e.hitDice")) }
    var hitDiceSpent: Int { min(level, max(0, Int(page.attributeNumber("dnd5e.hitDiceSpent") ?? 0))) }
    var hitDiceRemaining: Int { level - hitDiceSpent }

    /// Spends a hit die to heal: what was rolled (or the average) plus the Constitution modifier, at least 0.
    func spendHitDie(rolled: Int? = nil) {
        guard hitDiceRemaining > 0, let sides = hitDieSides else { return }
        let roll = rolled ?? LevelRules.averageRoll(hitDieSides: sides)
        page.setAttributeNumber("dnd5e.hitDiceSpent", Double(hitDiceSpent + 1))
        heal(max(0, roll + modifier(.constitution)))
    }

    // MARK: Spellcasting

    var spellcastingAbility: Ability? { SheetRules.spellcastingAbility(forClass: baseClassName) }

    var spellSaveDC: Int? { spellcastingAbility.map { SheetRules.spellSaveDC(proficiencyBonus: proficiencyBonus, abilityScore: scores[$0] ?? 10) } }
    var spellAttackBonus: Int? { spellcastingAbility.map { SheetRules.spellAttackBonus(proficiencyBonus: proficiencyBonus, abilityScore: scores[$0] ?? 10) } }

    /// The spell slots of each spell level, 1 to 9, at the character's level. A warlock's all are of one level.
    var slotsByLevel: [Int] {
        guard let progression else { return [Int](repeating: 0, count: 9) }
        if let pact = progression.pactSlots, let row = pact[safe: level - 1] {
            var slots = [Int](repeating: 0, count: 9)
            if (1...9).contains(row.level) { slots[row.level - 1] = row.count }
            return slots
        }
        return progression.slots?[safe: level - 1] ?? [Int](repeating: 0, count: 9)
    }

    var usesPactMagic: Bool { progression?.pactSlots != nil }

    /// How many slots of each level have been used.
    var slotsUsed: [Int] {
        let stored = page.attributeText("dnd5e.spellSlotsUsed").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let max = slotsByLevel
        return (0..<9).map { index in min(max[index], Swift.max(0, stored.indices.contains(index) ? stored[index] : 0)) }
    }

    var slotsRemaining: [Int] { zip(slotsByLevel, slotsUsed).map { $0 - $1 } }

    func setSlotsUsed(level slotLevel: Int, to count: Int) {
        guard (1...9).contains(slotLevel) else { return }
        var used = slotsUsed
        used[slotLevel - 1] = min(slotsByLevel[slotLevel - 1], max(0, count))
        page.setAttributeText("dnd5e.spellSlotsUsed", used.map(String.init).joined(separator: ","))
    }

    /// Spends a slot of a level. Returns false if there isn't one left.
    @discardableResult
    func spendSlot(level slotLevel: Int) -> Bool {
        guard (1...9).contains(slotLevel), slotsRemaining[slotLevel - 1] > 0 else { return false }
        setSlotsUsed(level: slotLevel, to: slotsUsed[slotLevel - 1] + 1)
        return true
    }

    // MARK: Spells

    /// The character's spells with their levels, cantrips first, then by level and name.
    var spells: [SheetSpell] {
        guard case .entries(let list)? = page.attributes["dnd5e.spells"] else { return [] }
        let library = Library.shared.entries(.spell, in: world.edition)
        return list.map { item in
            let entry = library.first { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            var spellLevel = 0
            if case .number(let value)? = entry?.attributes["dnd5e.spellLevel"] { spellLevel = Int(value) }
            return SheetSpell(name: item.name, entry: entry, level: spellLevel)
        }
        .sorted { ($0.level, $0.name.lowercased()) < ($1.level, $1.name.lowercased()) }
    }

    func effect(of spell: SheetSpell) -> SheetRules.SpellEffect {
        SheetRules.spellEffect(summary: spell.entry?.summary ?? "", spellLevel: spell.level, characterLevel: level, name: spell.name)
    }

    // MARK: Attacks

    /// The weapons among the character's equipment, matched to the library by name.
    var attacks: [SheetAttack] {
        guard case .entries(let list)? = page.attributes["dnd5e.equipment"] else { return [] }
        let equipment = Library.shared.entries(.equipment, in: world.edition)
        let weaponProficiencies = classAttributes["dnd5e.weaponProficiencies"].flatMap { value -> String? in
            if case .text(let text) = value { text } else { nil }
        } ?? ""
        var seen: Set<String> = []
        return list.compactMap { item -> SheetAttack? in
            guard let entry = equipment.first(where: { SheetRules.isSameItem($0.name, item.name) }),
                  let weapon = SheetRules.weapon(named: entry.name, attributes: entry.attributes),
                  seen.insert(entry.name).inserted
            else { return nil }
            let ability = weapon.ability(scores: scores)
            let isProficient = SheetRules.isProficient(with: weapon, proficiencies: weaponProficiencies)
            let mod = modifier(ability)
            return SheetAttack(
                weapon: weapon, ability: ability, isProficient: isProficient,
                attackBonus: mod + (isProficient ? proficiencyBonus : 0),
                damage: weapon.damage.adding(mod), versatileDamage: weapon.versatileDamage.map { $0.adding(mod) }
            )
        }
    }

    // MARK: Rests

    func shortRest() {
        // Pact magic comes back on a short rest.
        if usesPactMagic { page.setAttributeText("dnd5e.spellSlotsUsed", "") }
    }

    /// Everything comes back, and half the hit dice (at least one).
    func longRest() {
        page.setAttributeNumber("dnd5e.currentHitPoints", Double(maximumHitPoints))
        page.setAttributeNumber("dnd5e.temporaryHitPoints", 0)
        resetDeathSaves()
        // A long rest takes away one level of exhaustion.
        if conditionState.exhaustion > 0 { setExhaustion(conditionState.exhaustion - 1) }
        page.setAttributeText("dnd5e.spellSlotsUsed", "")
        page.setAttributeNumber("dnd5e.hitDiceSpent", Double(max(0, hitDiceSpent - max(1, level / 2))))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
