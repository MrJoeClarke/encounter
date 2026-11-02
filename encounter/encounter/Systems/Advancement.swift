//
//  Advancement.swift
//  encounter
//

import Foundation

/// How a system's characters gain levels, as data: where the level is kept, how high it goes, the numbers that change when a
/// level is reached, and what a character picks.
nonisolated struct AdvancementRule: Equatable, Sendable {
    struct Gain: Equatable, Sendable {
        /// The attribute that changes.
        var key: String
        /// What it becomes, as a formula. It can use `level` (the new level), `previousLevel`, and `current` (what the attribute
        /// is now, or 0), as well as the system's own named formulas.
        var formula: String
    }

    /// What a pick needs the player to say, beyond which pick it is.
    enum Target: Equatable, Sendable {
        /// Pick `count` of these number attributes, each once and none already marked, and add `increase` to each. The ones
        /// picked are listed in the `marks` attribute until a clear takes them off.
        case attributes(keys: [String], count: Int, increase: Int, marks: String)
        /// Pick `count` entries of a list whose text is a signed number, and add `increase` to each.
        case entryValues(key: String, count: Int, increase: Int)
        /// Pick a library entry that passes the filter and add it to a list.
        case libraryEntry(list: LibraryList, key: String, filter: EntryFilter)
        /// Add the next features of the subclass chosen at a step (or role) to a list.
        case nextSubclassFeatures(role: String, key: String)
        /// Name something new and add it to a list, with the same value text each time.
        case newEntry(key: String, valueText: String)
    }

    /// One of the things a character can pick when they reach a level, such as another hit point slot.
    struct Choice: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        /// How many of a level's points it uses.
        var cost: Int = 1
        /// What picking it does. A formula can use `current` and `level` as in `Gain`.
        var gains: [Gain] = []
        var target: Target?
        /// The levels it applies on, for what is always taken. Nil for every level.
        var onLevels: Set<Int>?
    }

    /// Takes a mark off at some levels, such as the traits that can be raised again.
    struct Clear: Equatable, Sendable {
        var levels: Set<Int>
        var key: String
    }

    var levelKey: String
    var maxLevel: Int
    /// What every level gives.
    var gains: [Gain]
    /// What a character spends `choicePoints` on each level. None if levels have no choices.
    var choices: [Choice] = []
    var choicePoints = 0
    /// What is always taken, on its levels, with whatever the player must say for it.
    var required: [Choice] = []
    var clears: [Clear] = []

    /// Whether the picks, by id (the same one can be picked twice), use exactly the points a level gives.
    func isValid(picks: [String]) -> Bool {
        guard choicePoints > 0 else { return picks.isEmpty }
        let costs = picks.compactMap { id in choices.first { $0.id == id }?.cost }
        return costs.count == picks.count && costs.reduce(0, +) == choicePoints
    }

    /// What is always taken on a level.
    func required(onLevel level: Int) -> [Choice] {
        required.filter { $0.onLevels?.contains(level) ?? true }
    }
}

/// One pick made on levelling up, with what the player said for it.
nonisolated struct LevelUpPick: Equatable, Sendable {
    var id: String
    /// Attribute keys, entry names, library keys, or a typed name, as the pick's target needs.
    var selections: [String] = []
}

nonisolated struct LevelUpResult {
    /// The numbers that changed.
    var changes: [(key: String, from: Double, to: Double)] = []
    /// What else was taken, as lines to show.
    var notes: [String] = []
}

@MainActor
enum Advancement {
    static func level(of page: Page, rule: AdvancementRule) -> Int {
        max(1, min(rule.maxLevel, Int(page.attributeNumber(rule.levelKey) ?? 1)))
    }

    static func canLevelUp(_ page: Page, rule: AdvancementRule) -> Bool {
        page.kind == .character && level(of: page, rule: rule) < rule.maxLevel
    }

    // MARK: What can be picked

    /// The attributes still open to a pick that raises some of a list (those not marked).
    static func openAttributes(keys: [String], marks: String, on page: Page) -> [String] {
        let marked = Set(page.attributeText(marks).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return keys.filter { !marked.contains($0) }
    }

    /// The library entries a pick of a library entry offers a page, for the level being taken.
    static func options(
        list: LibraryList, filter: EntryFilter, key: String, for page: Page, level: Int, system: any RuleSystem
    ) -> [LibraryEntry] {
        guard let world = page.world else { return [] }
        let have = Set((page.attributes[key].flatMap { value -> [EntryValue]? in if case .entries(let list) = value { list } else { nil } } ?? []).map(\.name))
        let inputs = ["level": Double(level)]
        return Library.shared.topLevelEntries(in: list, edition: world.edition).filter { entry in
            !have.contains(entry.name)
                && filter.matches(entry, chosen: { chosenAttributes($0, on: page, world: world) }, inputs: inputs, formulas: system.formulas)
        }
    }

    /// The attributes of the library entry a page chose for a role.
    static func chosenAttributes(_ role: String, on page: Page, world: World) -> [String: AttributeValue]? {
        switch page.reference(role: role) {
        case .library(let key): Library.shared.entry(forKey: key)?.attributes
        case .page(let target): target.attributes
        case .none: nil
        }
    }

    /// The features a subclass upgrade would add: the entries of the next level the subclass has beyond what the page holds.
    static func nextSubclassFeatures(role: String, key: String, on page: Page) -> [EntryValue] {
        guard let subclassKey = page.libraryKey(role: role), let subclass = Library.shared.entry(forKey: subclassKey) else { return [] }
        let held: [EntryValue] = { if case .entries(let list)? = page.attributes[key] { list } else { [] } }()
        let heldLevels = held.filter { $0.name.hasPrefix("\(subclass.name): ") }.compactMap(\.level)
        let next = (heldLevels.max() ?? 0) + 1
        return subclass.entries.filter { $0.level == next }
            .map { EntryValue(name: "\(subclass.name): \($0.name)", level: $0.level, text: $0.text) }
    }

    // MARK: Taking a level

    private static func signed(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    /// Whether the selections are enough for what a choice's target needs.
    static func isComplete(_ pick: LevelUpPick, choice: AdvancementRule.Choice, on page: Page, level: Int, system: any RuleSystem) -> Bool {
        let sel = pick.selections
        switch choice.target {
        case nil: return true
        case .attributes(let keys, let count, _, let marks)?:
            let open = Set(openAttributes(keys: keys, marks: marks, on: page))
            return sel.count == count && Set(sel).count == count && sel.allSatisfy(open.contains)
        case .entryValues(let key, let count, _)?:
            guard case .entries(let list)? = page.attributes[key] else { return false }
            let names = Set(list.map(\.name))
            return sel.count == count && Set(sel).count == count && sel.allSatisfy(names.contains)
        case .libraryEntry(let list, let key, let filter)?:
            let allowed = Set(options(list: list, filter: filter, key: key, for: page, level: level, system: system).map(\.key))
            return sel.count == 1 && allowed.contains(sel[0])
        case .nextSubclassFeatures(let role, let key)?:
            return !nextSubclassFeatures(role: role, key: key, on: page).isEmpty
        case .newEntry?:
            return sel.count == 1 && !sel[0].trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Raises the character one level and applies the gains, what is always taken for the new level, and the picks. Nil if the
    /// character can't level up, the picks don't use the points, or something a pick needs hasn't been said.
    @discardableResult
    static func levelUp(
        _ page: Page, rule: AdvancementRule, formulas: FormulaSet, system: (any RuleSystem)? = nil,
        picks: [LevelUpPick], required: [String: [String]] = [:]
    ) -> LevelUpResult? {
        guard canLevelUp(page, rule: rule), rule.isValid(picks: picks.map(\.id)) else { return nil }
        let previous = level(of: page, rule: rule)
        let new = previous + 1
        let system = system ?? NoRuleSystem()

        // Check everything before changing anything.
        let chosen = picks.compactMap { pick in rule.choices.first { $0.id == pick.id }.map { (pick, $0) } }
        let always = rule.required(onLevel: new).map { (LevelUpPick(id: $0.id, selections: required[$0.id] ?? []), $0) }
        for (pick, choice) in chosen + always where !isComplete(pick, choice: choice, on: page, level: new, system: system) { return nil }

        var result = LevelUpResult()
        page.setAttributeNumber(rule.levelKey, Double(new))
        for clear in rule.clears where clear.levels.contains(new) { page.setAttributeText(clear.key, "") }

        func set(_ key: String, to value: Double) {
            let current = page.attributeNumber(key) ?? 0
            guard value != current else { return }
            page.setAttributeNumber(key, value)
            if let index = result.changes.firstIndex(where: { $0.key == key }) { result.changes[index].to = value } else { result.changes.append((key, current, value)) }
        }
        func applyGains(_ gains: [AdvancementRule.Gain]) {
            for gain in gains {
                let inputs = ["level": Double(new), "previousLevel": Double(previous), "current": page.attributeNumber(gain.key) ?? 0]
                if let value = Formula(gain.formula)?.evaluate({ formulas.value($0, inputs) }) { set(gain.key, to: value) }
            }
        }
        func entries(_ key: String) -> [EntryValue] { if case .entries(let list)? = page.attributes[key] { list } else { [] } }

        applyGains(rule.gains)
        for (pick, choice) in always + chosen {
            applyGains(choice.gains)
            switch choice.target {
            case nil: break
            case .attributes(_, _, let increase, let marks)?:
                for key in pick.selections {
                    set(key, to: (page.attributeNumber(key) ?? 0) + Double(increase))
                    var marked = page.attributeText(marks).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    marked.append(key)
                    page.setAttributeText(marks, marked.joined(separator: ", "))
                }
            case .entryValues(let key, _, let increase)?:
                var list = entries(key)
                for name in pick.selections {
                    guard let index = list.firstIndex(where: { $0.name == name }) else { continue }
                    let value = Int(list[index].text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "+", with: "")) ?? 0
                    list[index].text = signed(value + increase)
                    result.notes.append("\(name) \(signed(value)) → \(signed(value + increase))")
                }
                page.attributes[key] = .entries(list)
            case .libraryEntry(_, let key, _)?:
                if let entry = Library.shared.entry(forKey: pick.selections[0]) {
                    page.attributes[key] = .entries(entries(key) + [EntryValue(name: entry.name, text: entry.detail ?? "")])
                    result.notes.append("\(choice.title): \(entry.name)")
                }
            case .nextSubclassFeatures(let role, let key)?:
                let added = nextSubclassFeatures(role: role, key: key, on: page)
                page.attributes[key] = .entries(entries(key) + added)
                result.notes += added.map { "\(choice.title): \($0.name)" }
            case .newEntry(let key, let valueText)?:
                let name = pick.selections[0].trimmingCharacters(in: .whitespaces)
                page.attributes[key] = .entries(entries(key) + [EntryValue(name: name, text: valueText)])
                result.notes.append("\(choice.title): \(name) \(valueText)")
            }
        }
        return result
    }

    /// The same, for picks that need nothing said.
    @discardableResult
    static func levelUp(_ page: Page, rule: AdvancementRule, formulas: FormulaSet, picks: [String] = []) -> [(key: String, from: Double, to: Double)]? {
        levelUp(page, rule: rule, formulas: formulas, picks: picks.map { LevelUpPick(id: $0) })?.changes
    }
}
