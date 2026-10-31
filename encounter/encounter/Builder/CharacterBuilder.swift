//
//  CharacterBuilder.swift
//  encounter
//

import Foundation
import SwiftData

/// Reads the races, classes, backgrounds and spells a character can be built from, in the library and in the world.
@MainActor
enum CharacterContent {
    static func races(in world: World) -> [ContentSource] {
        sources(.race, pageKind: .race, in: world)
    }

    static func classes(in world: World) -> [ContentSource] {
        sources(.class, pageKind: .characterClass, in: world)
    }

    static func backgrounds(in world: World) -> [ContentSource] {
        sources(.background, pageKind: .background, in: world)
    }

    /// The library's entries of a kind, then the world's own pages of the matching kind. Only the library's top-level
    /// entries are listed: a subrace or subclass is chosen after its parent.
    private static func sources(_ kind: LibraryKind, pageKind: PageKind, in world: World) -> [ContentSource] {
        var result: [ContentSource] = []
        if RuleSystems.system(for: world.system).hasContentLibrary {
            result += Library.shared.topLevelEntries(kind, in: world.edition).map { source(for: $0) }
        }
        let pages = (world.pages ?? []).filter { $0.kind == pageKind }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        result += pages.map { source(for: $0) }
        return result
    }

    static func source(for entry: LibraryEntry, subrace: LibraryEntry? = nil) -> ContentSource {
        let merged = Library.shared.traits(of: subrace ?? entry)
        return ContentSource(choice: .library(entry.key), name: subrace?.name ?? entry.name, summary: entry.summary,
                             attributes: merged.attributes, entries: merged.entries, libraryKey: (subrace ?? entry).key)
    }

    static func source(for page: Page) -> ContentSource {
        let entriesKey = page.kind == .characterClass ? CoreAttributes.featuresKey : page.kind == .race ? CoreAttributes.traitsKey : CoreAttributes.detailsKey
        var entries: [EntryValue] = []
        if case .entries(let list)? = page.attributes[entriesKey] { entries = list }
        return ContentSource(choice: .page(page.id), name: Mention.displayTitle(of: page.title), summary: page.summary,
                             attributes: page.attributes, entries: entries, libraryKey: page.basedOnKey)
    }

    /// The source a choice points at, with a subrace folded in for the 2014 rules.
    static func resolve(_ choice: ContentChoice?, subrace: String? = nil, in world: World) -> ContentSource? {
        switch choice {
        case .library(let key)?:
            guard let entry = Library.shared.entry(forKey: key) else { return nil }
            return source(for: entry, subrace: subrace.flatMap { Library.shared.entry(forKey: $0) })
        case .page(let id)?:
            return world.pages?.first { $0.id == id }.map { source(for: $0) }
        case nil:
            return nil
        }
    }

    /// The subraces a library race has.
    static func subraces(of race: ContentSource, in world: World) -> [LibraryEntry] {
        guard case .library(let key) = race.choice, let entry = Library.shared.entry(forKey: key) else { return [] }
        return Library.shared.children(of: entry, in: LibraryEdition(key: key) ?? world.edition)
    }

    /// The subclasses a class picks at level 1: those with a feature at level 1, which is true of some classes in the 2014 rules.
    static func levelOneSubclasses(of characterClass: ContentSource, in world: World) -> [LibraryEntry] {
        guard case .library(let key) = characterClass.choice, let entry = Library.shared.entry(forKey: key) else { return [] }
        return Library.shared.children(of: entry, in: LibraryEdition(key: key) ?? world.edition)
            .filter { $0.entries.contains { $0.level == 1 } }
    }

    /// The tools of each kind a character can choose from. In the 2014 rules each is an entry of the library, and in the
    /// 2024 rules musical instruments and gaming sets are variants listed in one entry.
    static func toolOptions(in world: World) -> [ToolCategory: [String]] {
        guard RuleSystems.system(for: world.system).hasContentLibrary else { return [:] }
        var options: [ToolCategory: [String]] = [:]
        for entry in Library.shared.entries(.equipment, in: world.edition) {
            guard case .text(let category)? = entry.attributes["dnd5e.equipmentCategory"],
                  let kind = ToolCategory.of(equipmentCategory: category, name: entry.name)
            else { continue }
            if let variants = entry.entries.first(where: { $0.name == "Variants" })?.text {
                // "Dice (1 SP), dragonchess (1 GP), playing cards (5 SP)": the names before the brackets.
                let names = EquipmentGroup.items(in: variants).map { $0.components(separatedBy: " (").first ?? $0 }
                options[kind, default: []] += names.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            } else if category.lowercased().contains(kind.rawValue) && entry.name.lowercased() != ToolCategory.gaming.title.lowercased() {
                options[kind, default: []].append(entry.name)
            }
        }
        return options.mapValues { $0.sorted() }
    }

    /// The spells of a level on a class's list. A class made in the world from a library class has its list.
    static func spells(level: Int, for characterClass: ContentSource, in world: World) -> [LibraryEntry] {
        guard let classKey = characterClass.libraryKey, let libraryClass = Library.shared.entry(forKey: classKey) else { return [] }
        let className = libraryClass.name
        return Library.shared.entries(.spell, in: world.edition).filter { spell in
            guard case .number(let spellLevel)? = spell.attributes["dnd5e.spellLevel"], Int(spellLevel) == level,
                  case .text(let classes)? = spell.attributes["dnd5e.spellClasses"]
            else { return false }
            return classes.components(separatedBy: ", ").contains(className)
        }
    }
}

/// Makes the character page from a draft.
@MainActor
enum CharacterBuilder {
    @discardableResult
    static func create(
        _ draft: CharacterDraft,
        plan: CharacterPlan,
        race: ContentSource,
        characterClass: ContentSource,
        background: ContentSource,
        subclass: LibraryEntry?,
        in world: World,
        context: ModelContext
    ) -> Page {
        let page = world.addPage(kind: .character, in: context)
        page.title = draft.name.trimmingCharacters(in: .whitespaces)
        page.characterRole = .playable
        page.summary = "\(race.name) \(characterClass.name), level 1"

        // What the character is.
        page.setReference(reference(for: draft.race, subrace: draft.subrace, in: world), role: LinkRole.race, in: context)
        page.setReference(reference(for: draft.characterClass, in: world), role: LinkRole.characterClass, in: context)
        page.setReference(reference(for: draft.background, in: world), role: LinkRole.background, in: context)
        if let subclass { page.setLibraryKey(subclass.key, role: "subclass") }
        page.setAttributeNumber("dnd5e.classLevel", 1)
        page.setAttributeText("dnd5e.alignment", draft.alignment)
        page.setAttributeText("core.creatureType", "Humanoid")

        // Numbers.
        for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, Double(plan.scores[ability] ?? 10)) }
        page.setAttributeNumber("dnd5e.hitPoints", plan.hitPoints.map(Double.init))
        page.setAttributeText("dnd5e.hitDice", plan.hitDie.map { "1\($0)" } ?? "")
        page.setAttributeNumber("dnd5e.armorClass", plan.armorClass.map(Double.init))
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(plan.proficiencyBonus))
        page.setAttributeText("dnd5e.speed", race.text("dnd5e.speed") ?? "")
        page.setAttributeText("dnd5e.size", race.text("core.raceSize") ?? "")
        page.setAttributeText("dnd5e.savingThrowProficiencies", plan.savingThrows.joined(separator: ", "))
        page.setAttributeText("dnd5e.skillProficiencies", plan.skills.joined(separator: ", "))
        page.setAttributeText("dnd5e.characterToolProficiencies", plan.tools.joined(separator: ", "))

        // Traits and features.
        let traits = race.entries
        if !traits.isEmpty { page.attributes["dnd5e.racialTraits"] = .entries(traits) }
        var features = characterClass.entries.filter { $0.level == 1 }
        if let subclass { features += subclass.entries.filter { $0.level == 1 }.map { EntryValue(name: "\(subclass.name): \($0.name)", level: 1, text: $0.text) } }
        if !features.isEmpty { page.attributes["dnd5e.classFeatures"] = .entries(features) }

        // Equipment and spells, as lists the creator can edit.
        if !plan.equipment.isEmpty { page.attributes["dnd5e.equipment"] = .entries(plan.equipment.map { EntryValue(name: $0, text: "") }) }
        let chosenSpells = (draft.cantrips.sorted() + draft.spells.sorted()).compactMap { Library.shared.entry(forKey: $0) }
        if !chosenSpells.isEmpty {
            page.attributes["dnd5e.spells"] = .entries(chosenSpells.map { EntryValue(name: $0.name, text: $0.spellHeadline) })
        }
        if !plan.notes.isEmpty {
            page.body = AttributedString("Still to fill in:\n" + plan.notes.map { "• \($0)" }.joined(separator: "\n"))
        }
        return page
    }

    private static func reference(for choice: ContentChoice?, subrace: String? = nil, in world: World) -> ContentReference {
        switch choice {
        case .library(let key)?: .library(subrace ?? key)
        case .page(let id)?: world.pages?.first { $0.id == id }.map(ContentReference.page) ?? .none
        case nil: .none
        }
    }
}
