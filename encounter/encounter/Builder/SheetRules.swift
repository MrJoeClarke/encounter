//
//  SheetRules.swift
//  encounter
//

import Foundation

/// The reading of weapons and spells that the character sheet's action cards need, kept apart from the screens so
/// it can be tested.
nonisolated enum SheetRules {
    // MARK: Spellcasting

    /// The ability a class casts with.
    static func spellcastingAbility(forClass name: String) -> Ability? {
        switch name {
        case "Bard", "Paladin", "Sorcerer", "Warlock": .charisma
        case "Cleric", "Druid", "Ranger": .wisdom
        case "Wizard": .intelligence
        default: nil
        }
    }

    static func spellSaveDC(proficiencyBonus: Int, abilityScore: Int) -> Int {
        DnD5eSystem.formulaSet.integer("spellSaveDC", ["proficiencyBonus": Double(proficiencyBonus), "score": Double(abilityScore)]) ?? 8
    }

    static func spellAttackBonus(proficiencyBonus: Int, abilityScore: Int) -> Int {
        DnD5eSystem.formulaSet.integer("spellAttackBonus", ["proficiencyBonus": Double(proficiencyBonus), "score": Double(abilityScore)]) ?? 0
    }

    // MARK: Weapons

    struct Weapon: Equatable, Sendable {
        var name: String
        var damage: DiceExpression
        var damageType: String
        var category: String
        var properties: [String]
        var versatileDamage: DiceExpression?

        var isRanged: Bool { category.localizedCaseInsensitiveContains("ranged") }
        var isFinesse: Bool { has("finesse") }
        var isThrown: Bool { has("thrown") }
        var range: String? {
            properties.first { $0.localizedCaseInsensitiveContains("range") }
        }

        func has(_ property: String) -> Bool {
            properties.contains { $0.localizedCaseInsensitiveCompare(property) == .orderedSame || $0.lowercased().hasPrefix(property.lowercased() + " ") }
        }

        /// The ability the attack and damage use. Finesse takes the better of Strength and Dexterity, and a ranged
        /// weapon uses Dexterity.
        func ability(scores: [Ability: Int]) -> Ability {
            let strength = scores[.strength] ?? 10, dexterity = scores[.dexterity] ?? 10
            if isFinesse { return dexterity > strength ? .dexterity : .strength }
            return isRanged ? .dexterity : .strength
        }
    }

    /// A weapon from a library equipment entry, or nil if it isn't one (it has no damage).
    static func weapon(named name: String, attributes: [String: AttributeValue]) -> Weapon? {
        guard case .text(let damage)? = attributes["dnd5e.damage"],
              let dice = damage.split(separator: " ", maxSplits: 1).first.flatMap({ DiceExpression(String($0)) })
        else { return nil }
        let type = damage.split(separator: " ", maxSplits: 1).dropFirst().first.map { $0.lowercased() } ?? ""
        var category = ""
        if case .text(let text)? = attributes["dnd5e.equipmentCategory"] { category = text }
        var properties: [String] = []
        var versatile: DiceExpression?
        if case .text(let text)? = attributes["dnd5e.weaponProperties"] {
            properties = splitProperties(text)
            if let open = text.range(of: "ersatile ("), let close = text[open.upperBound...].firstIndex(of: ")") {
                versatile = DiceExpression(String(text[open.upperBound..<close]))
            }
        }
        return Weapon(name: name, damage: dice, damageType: type, category: category, properties: properties, versatileDamage: versatile)
    }

    /// "Finesse, light, thrown (range 20/60)" in separate properties, without splitting inside brackets.
    static func splitProperties(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if character == ",", depth == 0 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result.filter { !$0.isEmpty }
    }

    /// An item as the builder or a person might have written it, reduced to the name an equipment entry has:
    /// "a longsword", "two handaxes" and "Dagger (2)" become "longsword", "handaxe" and "dagger".
    static func itemName(_ text: String) -> String {
        var name = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let open = name.firstIndex(of: "(") { name = String(name[..<open]).trimmingCharacters(in: .whitespaces) }
        let leading = ["a ", "an ", "the ", "one ", "two ", "three ", "four ", "five ", "six ", "ten ", "twenty "]
        var stripped = true
        while stripped {
            stripped = false
            for word in leading where name.hasPrefix(word) { name.removeFirst(word.count); stripped = true }
            if let digits = name.range(of: "^\\d+\\s*(x\\s*)?", options: .regularExpression) { name.removeSubrange(digits); stripped = true }
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Whether the names are the same item, allowing for a plural ("handaxes", "daggers", "knives").
    static func isSameItem(_ a: String, _ b: String) -> Bool {
        let x = itemName(a), y = itemName(b)
        if x == y || x == y + "s" || x == y + "es" || y == x + "s" || y == x + "es" { return true }
        return x.hasSuffix("ves") && x.dropLast(3) + "fe" == y || y.hasSuffix("ves") && y.dropLast(3) + "fe" == x
    }

    /// Whether a class's weapon proficiencies cover a weapon: "Simple weapons, martial weapons" covers everything, and
    /// "Daggers, darts, slings, quarterstaffs, light crossbows" covers those by name. The 2024 rogue and monk are
    /// proficient with martial weapons that have the Finesse or Light property.
    static func isProficient(with weapon: Weapon, proficiencies: String) -> Bool {
        let text = proficiencies.lowercased()
        let category = weapon.category.lowercased()
        if category.hasPrefix("simple"), text.contains("simple") { return true }
        if category.hasPrefix("martial") {
            if text.contains("martial weapons") && !text.contains("finesse or light") && !text.contains("that have") { return true }
            if text.contains("finesse or light"), weapon.isFinesse || weapon.has("light") { return true }
            if text.contains("martial and simple") || text.contains("simple and martial") { return true }
        }
        let name = weapon.name.lowercased()
        return text.split(whereSeparator: { ",;".contains($0) }).contains { isSameItem(String($0), name) }
    }

    // MARK: Spells

    struct SpellEffect: Equatable, Sendable {
        /// Made as a spell attack roll.
        var isAttack = false
        /// The ability the target saves with, if the spell asks for a saving throw.
        var save: Ability?
        var damage: DiceExpression?
        var damageType: String?
        var healing: DiceExpression?
        /// A healing spell adds the spellcasting ability modifier.
        var healingAddsModifier = false
        var halfOnSave = false
        /// The dice added for each slot level above the spell's own.
        var higherLevelDice: DiceExpression?
        /// What a higher-level slot adds one more of for each level, such as "dart", "ray" or "creature".
        var extraPerLevel: String?
        /// The darts or rays a spell makes, before higher slots.
        var baseProjectiles: Int?

        /// Darts and rays are made, each with its own damage. Creatures and the like are only counted.
        var hasProjectiles: Bool { baseProjectiles != nil && (extraPerLevel == "dart" || extraPerLevel == "ray") }
    }

    /// The darts or rays at a slot level: the spell's own number, and one more for each level above its own.
    static func projectiles(of effect: SpellEffect, spellLevel: Int, slotLevel: Int) -> Int? {
        guard effect.hasProjectiles, let base = effect.baseProjectiles else { return nil }
        return base + max(0, slotLevel - spellLevel)
    }

    private static let damageTypes = "acid|bludgeoning|cold|fire|force|lightning|necrotic|piercing|poison|psychic|radiant|slashing|thunder"

    /// What a spell asks the player to roll, found in its text. A spell that does something else, or that has
    /// several kinds of damage, only gives what could be read, and the card shows the text for the rest.
    static func spellEffect(summary: String, spellLevel: Int, characterLevel: Int, name: String = "") -> SpellEffect {
        var effect = SpellEffect()
        effect.isAttack = summary.range(of: "spell attack", options: .caseInsensitive) != nil
        if let match = summary.firstMatch(of: /(?i)(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throw/) {
            effect.save = Ability(name: String(match.1))
        }
        if let match = summary.firstMatch(of: try! Regex("(?i)(\\d+d\\d+(?:\\s*[+−-]\\s*\\d+)?)\\s+(\(damageTypes))\\s+damage")),
           let dice = match.output[1].substring.flatMap({ DiceExpression(String($0)) }) {
            effect.damage = dice
            effect.damageType = match.output[2].substring.map { $0.lowercased() }
        }
        if let match = summary.firstMatch(of: /(?i)regains?\s+(?:a number of\s+)?hit points equal to\s+(\d+d\d+)/),
           let dice = DiceExpression(String(match.1)) {
            effect.healing = dice
            effect.healingAddsModifier = summary.localizedCaseInsensitiveContains("spellcasting ability modifier")
        }
        effect.halfOnSave = summary.range(of: "half as much damage", options: .caseInsensitive) != nil
        if let match = summary.firstMatch(of: /(?i)(?:increases?|rises?) by\s+(\d+d\d+)\s+for each (?:spell )?slot level above/) {
            effect.higherLevelDice = DiceExpression(String(match.1))
        }
        if let match = summary.firstMatch(of: /(?i)(?:one (?:more|additional)|an additional) ([A-Za-z]+) for each (?:spell )?slot level above/) {
            effect.extraPerLevel = String(match.1).lowercased()
        }
        if let match = summary.firstMatch(of: /(?i)(?:create|hurl|fire) (one|two|three|four|five|six|seven|eight|nine) (?:glowing |fiery )?(dart|ray)s/),
           let count = CharacterRules.number(from: String(match.1)) {
            effect.baseProjectiles = count
        }
        // A cantrip's damage grows with the character's level: 1 die at levels 1 to 4, 2 at 5, 3 at 11 and 4 at 17.
        if spellLevel == 0, var damage = effect.damage, damage.count == 1, name != "Eldritch Blast" {
            damage.count = cantripDice(forLevel: characterLevel)
            effect.damage = damage
        }
        return effect
    }

    static func cantripDice(forLevel level: Int) -> Int {
        1 + (level >= 5 ? 1 : 0) + (level >= 11 ? 1 : 0) + (level >= 17 ? 1 : 0)
    }

    /// The damage a spell does when cast with a slot of a level, with the higher-level dice added.
    static func damage(of effect: SpellEffect, spellLevel: Int, slotLevel: Int) -> DiceExpression? {
        guard var damage = effect.damage else { return nil }
        if let extra = effect.higherLevelDice, slotLevel > spellLevel, spellLevel > 0 {
            damage.count += extra.count * (slotLevel - spellLevel)
        }
        return damage
    }

    static func healing(of effect: SpellEffect, spellLevel: Int, slotLevel: Int, abilityModifier: Int) -> DiceExpression? {
        guard var healing = effect.healing else { return nil }
        if let extra = effect.higherLevelDice, slotLevel > spellLevel, spellLevel > 0 {
            healing.count += extra.count * (slotLevel - spellLevel)
        }
        return effect.healingAddsModifier ? healing.adding(abilityModifier) : healing
    }
}
