//
//  RulesTextParsers.swift
//  encounter
//

import Foundation

/// Readers for the rules text of the library, whose races, classes and backgrounds word what they give a character as
/// sentences. Each takes the text as the rules print it and returns nil, or a note, for what it can't read, so the
/// builder can say so and let the creator fill it in.

/// What a race adds to the ability scores (the 2014 rules).
nonisolated struct AbilityBonuses: Equatable, Sendable {
    var fixed: [Ability: Int] = [:]
    /// Abilities of the player's choice, each given the same bonus: "two other ability scores of your choice increase by 1".
    var choices: (count: Int, amount: Int)?
    var isUnderstood = true

    static func == (lhs: AbilityBonuses, rhs: AbilityBonuses) -> Bool {
        lhs.fixed == rhs.fixed && lhs.choices?.count == rhs.choices?.count && lhs.choices?.amount == rhs.choices?.amount && lhs.isUnderstood == rhs.isUnderstood
    }

    /// Reads "Your Strength score increases by 2, and your Charisma score increases by 1.", "Your ability scores each
    /// increase by 1." and "Your Charisma score increases by 2, and two other ability scores of your choice increase by 1."
    static func parse(_ text: String) -> AbilityBonuses {
        var result = AbilityBonuses()
        let lowered = text.lowercased()

        if lowered.contains("ability scores each increase by") {
            let amount = firstNumber(after: "each increase by", in: lowered) ?? 1
            for ability in Ability.allCases { result.fixed[ability] = amount }
            return result
        }
        let named = try! NSRegularExpression(pattern: "your (strength|dexterity|constitution|intelligence|wisdom|charisma) score increases by (\\d+)")
        let ns = lowered as NSString
        for match in named.matches(in: lowered, range: NSRange(location: 0, length: ns.length)) {
            if let ability = Ability(name: ns.substring(with: match.range(at: 1))), let amount = Int(ns.substring(with: match.range(at: 2))) {
                result.fixed[ability, default: 0] += amount
            }
        }
        let choice = try! NSRegularExpression(pattern: "(\\w+) other ability scores of your choice increase by (\\d+)")
        if let match = choice.firstMatch(in: lowered, range: NSRange(location: 0, length: ns.length)),
           let count = CharacterRules.number(from: ns.substring(with: match.range(at: 1))),
           let amount = Int(ns.substring(with: match.range(at: 2))) {
            result.choices = (count, amount)
        }
        result.isUnderstood = !result.fixed.isEmpty || result.choices != nil
        return result
    }

    private static func firstNumber(after phrase: String, in text: String) -> Int? {
        guard let range = text.range(of: phrase) else { return nil }
        return Int(text[range.upperBound...].drop { !$0.isNumber }.prefix { $0.isNumber })
    }
}

/// A list of skills to choose from, and how many to choose.
nonisolated struct SkillChoice: Equatable, Sendable {
    var count: Int
    var options: [String]

    /// Every skill, for a class that may choose any ("Choose any three", "Choose any 3 skills").
    static let allSkills = ["Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception", "History", "Insight", "Intimidation", "Investigation",
                            "Medicine", "Nature", "Perception", "Performance", "Persuasion", "Religion", "Sleight of Hand", "Stealth", "Survival"]

    /// Reads "Choose two skills from Acrobatics, Athletics, and Survival", "Choose two from Arcana and History",
    /// "Choose 2: Animal Handling, Athletics, or Survival" and "Choose any three".
    static func parse(_ text: String) -> SkillChoice? {
        let anything = try! NSRegularExpression(pattern: "^\\s*Choose any (\\w+)", options: [.caseInsensitive])
        let whole = text as NSString
        if let match = anything.firstMatch(in: text, range: NSRange(location: 0, length: whole.length)),
           let count = CharacterRules.number(from: whole.substring(with: match.range(at: 1))) {
            return SkillChoice(count: count, options: allSkills)
        }
        let pattern = try! NSRegularExpression(pattern: "^\\s*Choose (\\w+)(?: skills)?(?: from|:)\\s*(.+?)\\.?\\s*$", options: [.caseInsensitive])
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let count = CharacterRules.number(from: ns.substring(with: match.range(at: 1)))
        else { return nil }
        return SkillChoice(count: count, options: SkillList.parse(ns.substring(with: match.range(at: 2))))
    }
}

nonisolated enum SkillList {
    /// Reads "Insight, Religion", "Insight and Religion" and "Athletics, Insight, and Survival".
    static func parse(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: ", and ", with: ", ")
            .replacingOccurrences(of: ", or ", with: ", ")
            .replacingOccurrences(of: " and ", with: ", ")
            .replacingOccurrences(of: " or ", with: ", ")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// A group of starting equipment: either what you get, or a choice between packages.
nonisolated struct EquipmentGroup: Equatable, Sendable {
    /// One option is a fixed item. Several are a choice, each with the letter the rules give it.
    var options: [Option]

    struct Option: Equatable, Sendable {
        var label: String
        var text: String
    }

    var isChoice: Bool { options.count > 1 }

    /// Reads a class's or background's starting equipment, in either edition's wording:
    /// - "Choose A or B: (A) Greataxe, 4 Handaxes; or (B) 75 GP" (2024), as one group.
    /// - Bullets such as "• (a) a greataxe or (b) any martial weapon" and "• An explorer's pack and four javelins" (2014),
    ///   with a group for each.
    /// - A plain list, as one fixed group.
    static func parse(_ text: String) -> [EquipmentGroup] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Choose "), let colon = trimmed.firstIndex(of: ":") {
            let options = lettered(String(trimmed[trimmed.index(after: colon)...]), uppercase: true)
            return options.isEmpty ? [EquipmentGroup(options: [Option(label: "", text: trimmed)])] : [EquipmentGroup(options: options)]
        }
        var groups: [EquipmentGroup] = []
        for line in trimmed.components(separatedBy: "\n") {
            var item = line.trimmingCharacters(in: .whitespaces)
            if item.hasPrefix("•") { item = item.dropFirst().trimmingCharacters(in: .whitespaces) }
            guard !item.isEmpty, !item.hasPrefix("You start with") else { continue }
            let options = lettered(item, uppercase: false)
            groups.append(EquipmentGroup(options: options.isEmpty ? [Option(label: "", text: item)] : options))
        }
        return groups
    }

    /// Names that contain "and", which doesn't separate two items there.
    private static let namesWithAnd = ["Block and Tackle"]

    /// The separate items in a package, such as "Spear, 5 Daggers, Explorer's Pack, and 11 GP" or "a light crossbow and 20 bolts".
    /// Commas and "and" separate items, except inside brackets and within a name like "Block and Tackle".
    static func items(in text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(0, depth - 1) }
            if (character == "," || character == ";") && depth == 0 {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)

        var items: [String] = []
        for piece in pieces {
            var text = piece.trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("and ") { text = String(text.dropFirst(4)) }
            if text.lowercased().hasPrefix("or ") { text = String(text.dropFirst(3)) }
            items += splitOnAnd(text)
        }
        return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func splitOnAnd(_ text: String) -> [String] {
        // Keep a name that contains "and" whole, and split what's around it.
        for name in namesWithAnd {
            if let range = text.range(of: name, options: .caseInsensitive) {
                let before = String(text[..<range.lowerBound])
                let after = String(text[range.upperBound...])
                return splitOnAnd(before) + [String(text[range])] + splitOnAnd(after)
            }
        }
        // Not inside brackets, and not a choice ("Artisan's Tools or Musical Instrument").
        var parts: [String] = []
        var current = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(0, depth - 1) }
            if depth == 0, text[index...].hasPrefix(" and ") {
                parts.append(current)
                current = ""
                index = text.index(index, offsetBy: 5)
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }
        parts.append(current)
        return parts
    }

    /// Splits "(a) one thing or (b) another" or "(A) one; (B) two; or (C) 155 GP" into its options.
    private static func lettered(_ text: String, uppercase: Bool) -> [Option] {
        let pattern = try! NSRegularExpression(pattern: "\\(([A-Za-z])\\)")
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // "(a chain)" isn't a letter in brackets, so a letter has to be followed by a space and start the text or follow punctuation.
        var options: [Option] = []
        for (index, match) in matches.enumerated() {
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let label = ns.substring(with: match.range(at: 1))
            var body = ns.substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound))
            body = body.trimmingCharacters(in: .whitespaces)
            for suffix in [" or", "; or", ";", ","] where body.hasSuffix(suffix) { body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) }
            if body.hasPrefix("or ") { body = String(body.dropFirst(3)) }
            options.append(Option(label: uppercase ? label.uppercased() : label, text: body))
        }
        return options
    }
}

/// How many spells a class chooses at level 1, from its Spellcasting feature.
nonisolated struct SpellLimits: Equatable, Sendable {
    enum Count: Equatable, Sendable {
        case none
        case fixed(Int)
        /// "a number of spells equal to your Wisdom modifier + your cleric level (minimum of one spell)".
        case abilityPlusLevel(Ability)
    }

    var cantrips = 0
    var spells = Count.none
    var ability: Ability?
    /// A wizard starts with six spells in a spellbook, and prepares fewer of them.
    var spellbook: Int?

    var isCaster: Bool { cantrips > 0 || spells != .none || ability != nil }

    /// Reads the level 1 Spellcasting text, 2014 or 2024. Pact Magic and Spellcasting alike.
    static func parse(_ text: String) -> SpellLimits {
        var limits = SpellLimits()
        let ns = text as NSString
        func firstMatch(_ pattern: String) -> [String]? {
            let expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            guard let m = expression.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
        if let g = firstMatch("you know (\\w+) (?:[A-Za-z]+ )?cantrips"), let n = CharacterRules.number(from: g[0]) { limits.cantrips = n }
        if let g = firstMatch("(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) is your spellcasting ability") { limits.ability = Ability(name: g[0]) }

        // 2014: "You know four 1st-level spells", or prepare "a number ... equal to your Wisdom modifier + your cleric level".
        if let g = firstMatch("you know (\\w+) 1st-level spells"), let n = CharacterRules.number(from: g[0]) {
            limits.spells = .fixed(n)
        } else if let g = firstMatch("equal to your (Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) modifier \\+ your \\w+ level"), let ability = Ability(name: g[0]) {
            limits.spells = .abilityPlusLevel(ability)
        }
        // 2024: "To start, choose four level 1 spells", "choose two level 1 Paladin spells", "choose four spells from your spellbook".
        if let g = firstMatch("to start, choose (\\w+) level 1 (?:[A-Za-z]+ )?spells"), let n = CharacterRules.number(from: g[0]) {
            limits.spells = .fixed(n)
        } else if let g = firstMatch("choose (\\w+) spells from your spellbook"), let n = CharacterRules.number(from: g[0]) {
            limits.spells = .fixed(n)
        }
        if let g = firstMatch("starts with (\\w+) (?:level 1|1st-level) (?:[A-Za-z]+ )?spells"), let n = CharacterRules.number(from: g[0]) {
            limits.spellbook = n
        }
        return limits
    }
}
