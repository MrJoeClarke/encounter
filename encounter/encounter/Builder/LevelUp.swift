//
//  LevelUp.swift
//  encounter
//

import Foundation
import SwiftData

/// A playable character, the class it levels in and what its next level asks for. Nil from `LevelUp.context(for:)`
/// when the character has no class with a table to level from, such as a class made from scratch.
@MainActor
struct LevelUpContext {
    let page: Page
    let world: World
    let characterClass: ContentSource
    let progression: ClassProgression
    let level: Int
    /// The subclasses the library has for the class, with the level it picks one at.
    let subclasses: [LibraryEntry]
    let subclassLevel: Int?
    let needs: LevelUpNeeds

    var scores: [Ability: Int] {
        Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, Int(page.attributeNumber($0.attributeKey) ?? 10)) })
    }

    /// The cantrips and spells of the class's list that the character could learn, by spell level.
    func spellOptions(level spellLevel: Int) -> [LibraryEntry] {
        let known = Set(knownSpellNames)
        return CharacterContent.spells(level: spellLevel, for: characterClass, in: world).filter { !known.contains($0.name) }
    }

    private var knownSpellNames: [String] {
        if case .entries(let list)? = page.attributes["dnd5e.spells"] { list.map(\.name) } else { [] }
    }

    /// The feats that can be taken in place of an ability increase. The 2024 rules give an Epic Boon at level 19.
    var featOptions: [LibraryEntry] {
        guard RuleSystems.system(for: world.system).hasContentLibrary else { return [] }
        let taken = Set(takenFeatNames)
        return Library.shared.entries(.feat, in: world.edition).filter { feat in
            guard !taken.contains(feat.name), feat.name != "Ability Score Improvement" else { return false }
            guard case .text(let category)? = feat.attributes["dnd5e.featCategory"] else { return true }
            if category.hasPrefix("Origin") { return false }
            if category.hasPrefix("Epic Boon") { return needs.newLevel >= 19 }
            return true
        }
    }

    private var takenFeatNames: [String] {
        if case .entries(let list)? = page.attributes["dnd5e.feats"] { list.map(\.name) } else { [] }
    }

    /// What is still needed before the level can be taken, empty when it can.
    func problems(for choices: LevelUpChoices) -> [String] {
        var problems: [String] = []
        if case .rolled(let roll) = choices.hitPoints, !(1...needs.hitDieSides).contains(roll) {
            problems.append(String(localized: "The roll must be between 1 and \(needs.hitDieSides)."))
        }
        if needs.choosesSubclass, choices.subclass.flatMap({ key in subclasses.first { $0.key == key } }) == nil, !subclasses.isEmpty {
            problems.append(String(localized: "Choose a subclass."))
        }
        if needs.hasImprovement {
            let increased = LevelRules.isValidIncrease(choices.abilityIncreases, to: scores)
            let tookFeat = choices.feat.flatMap { key in featOptions.first { $0.key == key } } != nil
            if !increased && !tookFeat { problems.append(String(localized: "Raise your ability scores by 2 points, or take a feat.")) }
        }
        if choices.cantrips.count != cantripsToChoose {
            problems.append(String(localized: "Choose \(cantripsToChoose) cantrips."))
        }
        if choices.spells.count != spellsToChoose {
            problems.append(String(localized: "Choose \(spellsToChoose) spells."))
        }
        return problems
    }

    /// How many cantrips and spells to choose: what the level gives, or fewer if the list has run out.
    var cantripsToChoose: Int { min(needs.cantripsToLearn, spellOptions(level: 0).count) }
    var spellsToChoose: Int {
        guard needs.spellsToLearn > 0, needs.highestSpellLevel > 0 else { return 0 }
        return min(needs.spellsToLearn, (1...needs.highestSpellLevel).reduce(0) { $0 + spellOptions(level: $1).count })
    }
}

@MainActor
enum LevelUp {
    /// Reads what levelling up a character involves, or nil if it can't be levelled: it isn't a playable character,
    /// has no class with a table, or is at level 20.
    static func context(for page: Page) -> LevelUpContext? {
        guard page.kind == .character, page.characterRole == .playable, let world = page.world else { return nil }
        let choice: ContentChoice
        switch page.reference(role: LinkRole.characterClass) {
        case .library(let key): choice = .library(key)
        case .page(let classPage): choice = .page(classPage.id)
        case .none: return nil
        }
        guard let characterClass = CharacterContent.resolve(choice, in: world),
              let progression = ClassProgression(attributes: characterClass.attributes)
        else { return nil }
        let level = Int(page.attributeNumber("dnd5e.classLevel") ?? 1)

        var subclasses: [LibraryEntry] = []
        if let key = characterClass.libraryKey, let entry = Library.shared.entry(forKey: key) {
            subclasses = Library.shared.children(of: entry, in: LibraryEdition(key: key) ?? world.edition)
        }
        // Every subclass of a class joins at the same level, which is the level of its first feature.
        let subclassLevel = subclasses.compactMap { $0.entries.compactMap(\.level).min() }.min()
        let hasSubclass = page.libraryKey(role: "subclass") != nil
        let wizard = characterClass.name == "Wizard" && characterClass.libraryKey != nil
        guard let needs = LevelRules.needs(
            for: progression, fromLevel: level, subclassLevel: subclassLevel, hasSubclass: hasSubclass,
            spellbookSpellsPerLevel: wizard ? 2 : 0
        ) else { return nil }
        return LevelUpContext(
            page: page, world: world, characterClass: characterClass, progression: progression, level: level,
            subclasses: subclasses, subclassLevel: subclassLevel, needs: needs
        )
    }

    /// The features of the class, and of the subclass if it has one, that come with a level.
    static func features(of context: LevelUpContext, subclass: LibraryEntry?, level: Int, upTo: Bool = false) -> [EntryValue] {
        func matches(_ feature: EntryValue) -> Bool { upTo ? (feature.level ?? 0) <= level && (feature.level ?? 0) >= 1 : feature.level == level }
        var result = context.characterClass.entries.filter(matches)
        if let subclass {
            result += subclass.entries.filter(matches).map {
                EntryValue(name: "\(subclass.name): \($0.name)", level: $0.level, text: $0.text)
            }
        }
        return result
    }

    /// Takes the next level. Returns a line for each change made.
    @discardableResult
    static func apply(_ choices: LevelUpChoices, to context: LevelUpContext, in modelContext: ModelContext) -> [String] {
        let page = context.page
        let needs = context.needs
        var changes: [String] = []

        // Ability scores first, since a higher Constitution counts towards this level's hit points.
        let oldScores = context.scores
        var newScores = oldScores
        if needs.hasImprovement, choices.feat == nil, LevelRules.isValidIncrease(choices.abilityIncreases, to: oldScores) {
            for (ability, points) in choices.abilityIncreases where points > 0 {
                newScores[ability] = min(CharacterRules.maximumScore, (oldScores[ability] ?? 10) + points)
                page.setAttributeNumber(ability.attributeKey, Double(newScores[ability] ?? 10))
                changes.append("\(ability.rawValue) \(oldScores[ability] ?? 10) → \(newScores[ability] ?? 10)")
            }
        }

        // Hit points.
        let roll: Int
        switch choices.hitPoints {
        case .average: roll = LevelRules.averageRoll(hitDieSides: needs.hitDieSides)
        case .rolled(let value): roll = min(max(value, 1), needs.hitDieSides)
        }
        let constitution = newScores[.constitution] ?? 10
        let gained = LevelRules.hitPointsGained(roll: roll, constitution: constitution)
            + LevelRules.retroactiveHitPoints(levelsBefore: context.level, oldConstitution: oldScores[.constitution] ?? 10, newConstitution: constitution)
        let hitPoints = Int(page.attributeNumber("dnd5e.hitPoints") ?? 0) + gained
        page.setAttributeNumber("dnd5e.hitPoints", Double(hitPoints))
        page.setAttributeText("dnd5e.hitDice", "\(needs.newLevel)d\(needs.hitDieSides)")
        changes.append(String(localized: "Hit points +\(gained) (now \(hitPoints))"))

        // Level and what comes with it.
        page.setAttributeNumber("dnd5e.classLevel", Double(needs.newLevel))
        let proficiencyBonus = CharacterRules.proficiencyBonus(atLevel: needs.newLevel)
        if proficiencyBonus != CharacterRules.proficiencyBonus(atLevel: context.level) {
            changes.append(String(localized: "Proficiency bonus +\(proficiencyBonus)"))
        }
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(proficiencyBonus))
        page.summary = page.summary.replacingOccurrences(of: ", level \\d+", with: ", level \(needs.newLevel)", options: .regularExpression)

        // A subclass chosen now brings the features it has up to this level.
        var subclass = page.libraryKey(role: "subclass").flatMap { Library.shared.entry(forKey: $0) }
        var gainedFeatures: [EntryValue]
        if needs.choosesSubclass, let key = choices.subclass, let chosen = context.subclasses.first(where: { $0.key == key }) {
            page.setLibraryKey(chosen.key, role: "subclass")
            subclass = chosen
            changes.append(String(localized: "Subclass: \(chosen.name)"))
            let all = features(of: context, subclass: chosen, level: needs.newLevel, upTo: true)
            let had = Set(existingFeatureNames(of: page))
            gainedFeatures = all.filter { !had.contains($0.name) }
        } else {
            gainedFeatures = features(of: context, subclass: subclass, level: needs.newLevel)
        }
        if !gainedFeatures.isEmpty {
            var list = existingEntries("dnd5e.classFeatures", of: page)
            list += gainedFeatures
            page.attributes["dnd5e.classFeatures"] = .entries(list)
            changes.append(String(localized: "Features: ") + gainedFeatures.map(\.name).joined(separator: ", "))
        }

        // A feat in place of the ability increase.
        if needs.hasImprovement, let key = choices.feat, let feat = Library.shared.entry(forKey: key) {
            var list = existingEntries("dnd5e.feats", of: page)
            list.append(EntryValue(name: feat.name, level: needs.newLevel, text: feat.summary))
            page.attributes["dnd5e.feats"] = .entries(list)
            changes.append(String(localized: "Feat: \(feat.name)"))
        }

        // Spells and slots.
        let learned = (choices.cantrips.sorted() + choices.spells.sorted()).compactMap { Library.shared.entry(forKey: $0) }
        if !learned.isEmpty {
            var list = existingEntries("dnd5e.spells", of: page)
            list += learned.map { EntryValue(name: $0.name, text: $0.spellHeadline) }
            page.attributes["dnd5e.spells"] = .entries(list)
            changes.append(String(localized: "Spells: ") + learned.map(\.name).joined(separator: ", "))
        }
        let slots = context.progression.slotsDescription(at: needs.newLevel)
        if context.progression.castsSpells {
            page.setAttributeText("dnd5e.spellSlots", slots)
            if !slots.isEmpty { changes.append(String(localized: "Spell slots: ") + slots) }
        }

        page.updateSearchText()
        return changes
    }

    private static func existingEntries(_ key: String, of page: Page) -> [EntryValue] {
        if case .entries(let list)? = page.attributes[key] { list } else { [] }
    }

    private static func existingFeatureNames(of page: Page) -> [String] {
        existingEntries("dnd5e.classFeatures", of: page).map(\.name)
    }
}
