//
//  ActionCards.swift
//  encounter
//

import Foundation

/// One roll an action asks for, said in words and as dice.
struct ActionRoll: Identifiable, Equatable {
    enum Kind: Equatable { case check, attack, save, damage, healing }

    var kind: Kind
    /// "Attack roll", "Damage", "Athletics check".
    var title: String
    var dice: DiceExpression
    /// Where the number added comes from: "Strength +3 · proficiency +2".
    var addedFrom: String
    /// Extra to say about it, such as "Half as much on a successful save".
    var note: String?
    /// What the character's conditions make of it: advantage or disadvantage to start with, lines to show, and for a
    /// roll that can't be made, why it is failed.
    var defaultMode = AdvantageMode.normal
    var conditionNotes: [String] = []
    var autoFail: String?
    var id: String { "\(title)|\(dice.text)" }

    /// Whether advantage and disadvantage can apply: only to a d20.
    var allowsAdvantage: Bool { dice.sides == 20 && dice.count == 1 }

    /// "Roll d20 + 5", which is what a player with real dice needs.
    var instruction: String { String(localized: "Roll \(dice.text)") }
}

/// What to do for an action on the sheet: the rolls to make, and what the player should know besides.
struct ActionCard: Equatable {
    var title: String
    var subtitle: String
    var rolls: [ActionRoll]
    /// Plain lines such as "Targets make a Dexterity saving throw against DC 14".
    var notes: [String]
    /// The full text of a spell, shown below.
    var text: String

    init(title: String, subtitle: String = "", rolls: [ActionRoll] = [], notes: [String] = [], text: String = "") {
        self.title = title
        self.subtitle = subtitle
        self.rolls = rolls
        self.notes = notes
        self.text = text
    }
}

extension CharacterSheet {
    private func signed(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    /// "Strength +3 · proficiency +2".
    private func addedFrom(_ ability: Ability, proficient: Bool) -> String {
        var parts = ["\(ability.rawValue) \(signed(modifier(ability)))"]
        if proficient { parts.append(String(localized: "proficiency \(signed(proficiencyBonus))")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Conditions

    /// Puts what the character's conditions do onto a roll: how it is made, a penalty, and what to say.
    /// `blocksRoll` is for a roll that is failed without being made, such as a Strength save while paralyzed. A check
    /// that fails only if it needs a sense is a note instead, since the sheet can't tell.
    private func applying(_ effect: RollConditionEffect, to roll: ActionRoll, blocksRoll: Bool) -> ActionRoll {
        var roll = roll
        var effect = effect
        roll.defaultMode = effect.mode
        if blocksRoll { roll.autoFail = effect.autoFail; effect.autoFail = nil }
        roll.conditionNotes = effect.notes
        if effect.penalty != 0 { roll.dice = roll.dice.adding(effect.penalty) }
        return roll
    }

    /// A line at the top of a card for an action when the character can't take actions.
    private var cantActNotes: [String] {
        let names = incapacitatingConditions.map(\.title)
        return names.isEmpty ? [] : [String(localized: "\(names.joined(separator: ", ")): you can't take actions or reactions.")]
    }

    // MARK: Checks

    /// " · half proficiency +1" for a character with Jack of All Trades, or nothing.
    private var halfProficiencyText: String {
        halfProficiency > 0 ? " · " + String(localized: "half proficiency \(signed(halfProficiency))") : ""
    }

    private func skillAddedFrom(_ skill: SheetSkill) -> String {
        let base = "\(skill.ability.rawValue) \(signed(modifier(skill.ability)))"
        switch skill.proficiency {
        case .none: return base
        case .half: return base + " · " + String(localized: "half proficiency \(signed(halfProficiency)) (Jack of All Trades)")
        case .proficient: return base + " · " + String(localized: "proficiency \(signed(proficiencyBonus))")
        case .expertise: return base + " · " + String(localized: "expertise \(signed(proficiencyBonus * 2)) (double proficiency)")
        }
    }

    /// A death saving throw: a bare d20, with no modifiers.
    var deathSaveCard: ActionCard {
        ActionCard(
            title: String(localized: "Death saving throw"),
            rolls: [ActionRoll(kind: .check, title: String(localized: "Death saving throw"), dice: .d20, addedFrom: String(localized: "No modifiers"),
                               note: String(localized: "10 or higher is a success and 9 or lower a failure. A 1 counts as two failures, and a 20 brings you back with 1 hit point."))],
            notes: [String(localized: "Three successes make you stable. Three failures mean death.")]
        )
    }

    func card(forAbility ability: Ability) -> ActionCard {
        ActionCard(
            title: String(localized: "\(ability.rawValue) check"),
            rolls: [applying(checkEffect, to: ActionRoll(kind: .check, title: String(localized: "\(ability.rawValue) check"), dice: DiceExpression.d20.adding(modifier(ability) + halfProficiency),
                                                         addedFrom: addedFrom(ability, proficient: false) + halfProficiencyText), blocksRoll: false)]
        )
    }

    func card(for save: SheetSave) -> ActionCard {
        let title = String(localized: "\(save.ability.rawValue) saving throw")
        return ActionCard(
            title: title,
            rolls: [applying(saveEffect(save.ability), to: ActionRoll(kind: .save, title: title, dice: DiceExpression.d20.adding(save.bonus), addedFrom: addedFrom(save.ability, proficient: save.isProficient)), blocksRoll: true)]
        )
    }

    func card(for skill: SheetSkill) -> ActionCard {
        let title = String(localized: "\(skill.name) check")
        return ActionCard(
            title: title, subtitle: skill.ability.rawValue,
            rolls: [applying(checkEffect, to: ActionRoll(kind: .check, title: title, dice: DiceExpression.d20.adding(skill.bonus), addedFrom: skillAddedFrom(skill)), blocksRoll: false)]
        )
    }

    var initiativeCard: ActionCard {
        ActionCard(
            title: String(localized: "Initiative"),
            rolls: [applying(initiativeEffect, to: ActionRoll(kind: .check, title: String(localized: "Initiative"), dice: DiceExpression.d20.adding(initiative), addedFrom: addedFrom(.dexterity, proficient: false) + halfProficiencyText), blocksRoll: false)]
        )
    }

    // MARK: Weapons

    func card(for attack: SheetAttack) -> ActionCard {
        let weapon = attack.weapon
        var rolls = [
            applying(attackEffect, to: ActionRoll(kind: .attack, title: String(localized: "Attack roll"), dice: DiceExpression.d20.adding(attack.attackBonus),
                       addedFrom: addedFrom(attack.ability, proficient: attack.isProficient),
                       note: attack.isProficient ? nil : String(localized: "Not proficient, so the proficiency bonus isn't added.")), blocksRoll: false),
            ActionRoll(kind: .damage, title: String(localized: "Damage"), dice: attack.damage,
                       addedFrom: "\(attack.ability.rawValue) \(signed(modifier(attack.ability)))",
                       note: String(localized: "On a natural 20, roll the damage dice twice.") + (weapon.damageType.isEmpty ? "" : " (\(weapon.damageType))"))
        ]
        if let versatile = attack.versatileDamage {
            rolls.append(ActionRoll(kind: .damage, title: String(localized: "Damage, two-handed"), dice: versatile,
                                    addedFrom: "\(attack.ability.rawValue) \(signed(modifier(attack.ability)))"))
        }
        var notes: [String] = cantActNotes
        if let range = weapon.range { notes.append(range) }
        let others = weapon.properties.filter { $0 != weapon.range && !$0.lowercased().hasPrefix("versatile") }
        if !others.isEmpty { notes.append(others.joined(separator: ", ")) }
        if weapon.isFinesse { notes.append(String(localized: "Finesse: Strength or Dexterity, whichever is higher, was used.")) }
        return ActionCard(title: weapon.name, subtitle: weapon.category, rolls: rolls, notes: notes)
    }

    // MARK: Spells

    /// What casting a spell asks for. `slotLevel` is the level of slot it is cast with, which only matters when the
    /// spell does more at a higher level. A cantrip, or a spell with nothing to roll, still gives its text.
    func card(for spell: SheetSpell, slotLevel: Int? = nil) -> ActionCard {
        let effect = effect(of: spell)
        let castAt = max(slotLevel ?? spell.level, spell.level)
        var rolls: [ActionRoll] = []
        var notes: [String] = cantActNotes
        let ability = spellcastingAbility
        let abilityText = ability.map { "\($0.rawValue) \(signed(modifier($0))) · " + String(localized: "proficiency \(signed(proficiencyBonus))") } ?? ""

        let projectiles = SheetRules.projectiles(of: effect, spellLevel: spell.level, slotLevel: castAt)
        let noun = effect.extraPerLevel ?? ""
        if effect.isAttack, let bonus = spellAttackBonus {
            var roll = applying(attackEffect, to: ActionRoll(kind: .attack, title: String(localized: "Spell attack"), dice: DiceExpression.d20.adding(bonus), addedFrom: abilityText), blocksRoll: false)
            if let projectiles {
                roll.title = String(localized: "Spell attack, for each \(noun)")
                roll.note = String(localized: "\(projectiles) \(noun)s: make a separate attack roll for each one.")
            }
            rolls.append(roll)
        }
        if let save = effect.save, let dc = spellSaveDC {
            notes.append(String(localized: "Each target makes a \(save.rawValue) saving throw against DC \(dc)."))
        }
        if var damage = SheetRules.damage(of: effect, spellLevel: spell.level, slotLevel: castAt) {
            let type = effect.damageType.map { " (\($0))" } ?? ""
            var note: String?
            var title = String(localized: "Damage") + type
            if effect.halfOnSave { note = String(localized: "Half as much on a successful save.") }
            if effect.isAttack { note = String(localized: "On a critical hit, roll the damage dice twice.") }
            if let projectiles {
                if effect.isAttack {
                    title = String(localized: "Damage for each \(noun) that hits") + type
                } else {
                    // The darts all hit, so their damage is rolled together: each has the dice and the number added.
                    damage = DiceExpression(count: damage.count * projectiles, sides: damage.sides, modifier: damage.modifier * projectiles)
                    title = String(localized: "Damage, \(projectiles) \(noun)s") + type
                    note = String(localized: "\(projectiles) \(noun)s, each dealing \(SheetRules.damage(of: effect, spellLevel: spell.level, slotLevel: castAt)?.text ?? ""). They can strike one creature or several.")
                }
            }
            rolls.append(ActionRoll(kind: .damage, title: title, dice: damage, addedFrom: "", note: note))
        }
        if !noun.isEmpty, projectiles == nil, castAt > spell.level {
            let extra = castAt - spell.level
            notes.append(String(localized: "Cast at \(ClassProgression.ordinal(castAt)) level: \(extra) more \(noun)\(extra == 1 ? "" : "s") than the spell's own number."))
        }
        if let healing = SheetRules.healing(of: effect, spellLevel: spell.level, slotLevel: castAt, abilityModifier: ability.map(modifier) ?? 0) {
            rolls.append(ActionRoll(kind: .healing, title: String(localized: "Healing"), dice: healing, addedFrom: ability.map { "\($0.rawValue) \(signed(modifier($0)))" } ?? ""))
        }
        if spell.name == "Eldritch Blast" {
            notes.append(String(localized: "\(SheetRules.cantripDice(forLevel: level)) beams: make a separate attack roll and damage roll for each."))
        }

        var facts: [String] = []
        for (key, label) in [("dnd5e.castingTime", ""), ("dnd5e.spellRange", ""), ("dnd5e.duration", "")] {
            if case .text(let value)? = spell.entry?.attributes[key], !value.isEmpty { facts.append(label + value) }
        }
        let level = spell.level == 0 ? String(localized: "Cantrip") : String(localized: "\(ClassProgression.ordinal(spell.level)) level")
        var subtitle = [level]
        if case .text(let school)? = spell.entry?.attributes["dnd5e.spellSchool"] { subtitle.append(school) }
        if slotLevel != nil, castAt > spell.level { subtitle.append(String(localized: "cast at \(ClassProgression.ordinal(castAt)) level")) }
        notes.append(contentsOf: facts.isEmpty ? [] : [facts.joined(separator: " · ")])
        return ActionCard(title: spell.name, subtitle: subtitle.joined(separator: " · "), rolls: rolls, notes: notes, text: spell.entry?.summary ?? "")
    }

    /// The slot levels a spell can be cast with: its own and up, where a slot is left. A cantrip needs none.
    func castableSlotLevels(for spell: SheetSpell) -> [Int] {
        guard spell.level > 0 else { return [] }
        return (spell.level...9).filter { slotsRemaining[$0 - 1] > 0 }
    }

    /// Casts a spell: spends a slot of the level (none for a cantrip, or a ritual cast without one). Returns whether
    /// the spell could be cast.
    @discardableResult
    func cast(_ spell: SheetSpell, slotLevel: Int?) -> Bool {
        if spell.level == 0 { return true }
        guard let slotLevel else { return spell.isRitual }
        guard slotLevel >= spell.level else { return false }
        return spendSlot(level: slotLevel)
    }
}
