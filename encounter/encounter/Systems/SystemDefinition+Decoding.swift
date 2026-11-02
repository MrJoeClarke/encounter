//
//  SystemDefinition+Decoding.swift
//  encounter
//

import Foundation

// How each piece of a system is written in a system file. Each reads plain JSON an author can write by hand, with a `type` where
// there are several kinds, and leaves out anything with a sensible default.

private func corrupt(_ decoder: any Decoder, _ message: String) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
}

// MARK: Rolls

nonisolated extension RollModel.Die: Decodable {
    private enum CodingKeys: String, CodingKey { case name, sides }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), sides: try c.decode(Int.self, forKey: .sides))
        guard sides >= 2 else { throw corrupt(decoder, "A die needs at least 2 sides.") }
    }
}

nonisolated extension RollModel.AdvantageRule: Decodable {
    private enum CodingKeys: String, CodingKey { case type, sides }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "rollTwice": self = .rollTwice
        case "bonusDie": self = .bonusDie(sides: try c.decode(Int.self, forKey: .sides))
        default: throw corrupt(decoder, "Advantage is “rollTwice” or “bonusDie”.")
        }
    }
}

nonisolated extension RollModel: Decodable {
    private enum CodingKeys: String, CodingKey { case dice, advantage, critical, criticalAlwaysMeetsTarget, fumbleAlwaysMisses }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dice = try c.decode([Die].self, forKey: .dice)
        guard !dice.isEmpty else { throw corrupt(decoder, "A roll needs at least one die.") }
        let critical: CriticalRule
        switch try c.decodeIfPresent(String.self, forKey: .critical) ?? "none" {
        case "naturalExtreme": critical = .naturalExtreme
        case "matchingDice": critical = .matchingDice
        case "none": critical = .none
        default: throw corrupt(decoder, "A critical is “naturalExtreme”, “matchingDice” or “none”.")
        }
        self.init(
            dice: dice, advantage: try c.decodeIfPresent(AdvantageRule.self, forKey: .advantage) ?? .rollTwice, critical: critical,
            criticalAlwaysMeetsTarget: try c.decodeIfPresent(Bool.self, forKey: .criticalAlwaysMeetsTarget) ?? false,
            fumbleAlwaysMisses: try c.decodeIfPresent(Bool.self, forKey: .fumbleAlwaysMisses) ?? false
        )
    }
}

// MARK: Rests and resources

nonisolated extension RestDefinition: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name))
    }
}

nonisolated extension Restoration: Decodable {
    private enum CodingKeys: String, CodingKey { case amount, formula, when }

    /// "full", "empty", or an object with an `amount` of "full" or "empty" or a `formula`, and optionally a `when` formula.
    init(from decoder: any Decoder) throws {
        if let word = try? decoder.singleValueContainer().decode(String.self) {
            switch word {
            case "full": self = .full
            case "empty": self = .empty
            default: throw corrupt(decoder, "A restoration is “full”, “empty”, or an object with a formula.")
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let when = try c.decodeIfPresent(String.self, forKey: .when)
        if let formula = try c.decodeIfPresent(String.self, forKey: .formula) {
            self.init(amount: .formula(formula), condition: when)
        } else {
            switch try c.decodeIfPresent(String.self, forKey: .amount) ?? "full" {
            case "full": self.init(amount: .full, condition: when)
            case "empty": self.init(amount: .empty, condition: when)
            default: throw corrupt(decoder, "An amount is “full” or “empty”; for anything else give a formula.")
            }
        }
    }
}

nonisolated extension ResourceDefinition: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name, key, storage, maximum, restoredBy, startsAt }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storage: Storage
        switch try c.decodeIfPresent(String.self, forKey: .storage) ?? "remaining" {
        case "remaining": storage = .remaining
        case "spent": storage = .spent
        case "spentList": storage = .spentList
        default: throw corrupt(decoder, "Storage is “remaining”, “spent” or “spentList”.")
        }
        self.init(
            id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name), key: try c.decode(String.self, forKey: .key),
            storage: storage, maximum: try c.decodeIfPresent(String.self, forKey: .maximum),
            restoredBy: try c.decodeIfPresent([String: Restoration].self, forKey: .restoredBy) ?? [:],
            startsAt: try c.decodeIfPresent(Double.self, forKey: .startsAt)
        )
    }
}

// MARK: Creation and advancement

nonisolated extension LibraryList: Decodable {
    private enum CodingKeys: String, CodingKey { case kind, subKind }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(LibraryKind.self, forKey: .kind), subKind: try c.decodeIfPresent(String.self, forKey: .subKind))
    }
}

nonisolated extension NumberRule.Entry: Decodable {
    private enum CodingKeys: String, CodingKey { case key, label, variable }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .key)
        self.init(
            key: key, label: try c.decodeIfPresent(String.self, forKey: .label) ?? key,
            variable: try c.decodeIfPresent(String.self, forKey: .variable) ?? key
        )
    }
}

nonisolated extension CreationStep: Decodable {
    private enum CodingKeys: String, CodingKey { case id, title, type, list, required, entries, assignFrom, range }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        switch try c.decode(String.self, forKey: .type) {
        case "concept": self.init(id: id, title: title, kind: .concept)
        case "review": self.init(id: id, title: title, kind: .review)
        case "choose":
            self.init(id: id, title: title, kind: .choose(list: try c.decode(LibraryList.self, forKey: .list), isRequired: try c.decodeIfPresent(Bool.self, forKey: .required) ?? true))
        case "numbers":
            let entries = try c.decode([NumberRule.Entry].self, forKey: .entries)
            if let numbers = try c.decodeIfPresent([Int].self, forKey: .assignFrom) {
                self.init(id: id, title: title, kind: .numbers(NumberRule(entries: entries, method: .assignFrom(numbers))))
            } else if let range = try c.decodeIfPresent([Int].self, forKey: .range), range.count == 2, range[0] <= range[1] {
                self.init(id: id, title: title, kind: .numbers(NumberRule(entries: entries, method: .free(range[0]...range[1]))))
            } else {
                throw corrupt(decoder, "Numbers need “assignFrom” (a list) or “range” (a lowest and a highest).")
            }
        default:
            throw corrupt(decoder, "A step is “concept”, “choose”, “numbers” or “review”.")
        }
    }
}

nonisolated extension CreationFlow: Decodable {
    private enum CodingKeys: String, CodingKey { case steps, derived, levelKey, startingLevel }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Starting numbers don't depend on each other, so they are kept in a fixed order by key.
        let derived = try c.decodeIfPresent([String: String].self, forKey: .derived) ?? [:]
        self.init(
            steps: try c.decode([CreationStep].self, forKey: .steps), derived: derived.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
            levelKey: try c.decodeIfPresent(String.self, forKey: .levelKey), startingLevel: try c.decodeIfPresent(Int.self, forKey: .startingLevel) ?? 1
        )
    }
}

nonisolated extension AdvancementRule.Gain: Decodable {
    private enum CodingKeys: String, CodingKey { case key, formula }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key), formula: try c.decode(String.self, forKey: .formula))
    }
}

nonisolated extension AdvancementRule: Decodable {
    private enum CodingKeys: String, CodingKey { case levelKey, maxLevel, gains }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            levelKey: try c.decode(String.self, forKey: .levelKey), maxLevel: try c.decode(Int.self, forKey: .maxLevel),
            gains: try c.decodeIfPresent([Gain].self, forKey: .gains) ?? []
        )
    }
}

// MARK: Conditions

nonisolated extension ConditionEffectRule: Decodable {
    private enum CodingKeys: String, CodingKey { case rolls, effect, note, formula, reason, when }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let effect: Effect
        switch try c.decode(String.self, forKey: .effect) {
        case "advantage": effect = .advantage
        case "disadvantage": effect = .disadvantage
        case "autoFail": effect = .autoFail(try c.decode(String.self, forKey: .note))
        case "penalty": effect = .penalty(formula: try c.decode(String.self, forKey: .formula), reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "")
        default: throw corrupt(decoder, "An effect is “advantage”, “disadvantage”, “autoFail” or “penalty”.")
        }
        self.init(Set(try c.decode([String].self, forKey: .rolls)), effect, when: try c.decodeIfPresent(String.self, forKey: .when))
    }
}

nonisolated extension ConditionDefinition: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name, hasLevels, effects }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try c.decode(String.self, forKey: .id), try c.decode(String.self, forKey: .name),
            hasLevels: try c.decodeIfPresent(Bool.self, forKey: .hasLevels) ?? false,
            effects: try c.decodeIfPresent([ConditionEffectRule].self, forKey: .effects) ?? []
        )
    }
}

// MARK: Sheet

nonisolated extension SheetRow: Decodable {
    private enum CodingKeys: String, CodingKey { case id, label, type, formula, inputs, roll, resource, key }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let label = try c.decodeIfPresent(String.self, forKey: .label) ?? id
        let inputs = try c.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        switch try c.decode(String.self, forKey: .type) {
        case "stat": self.init(id: id, label: label, kind: .stat(formula: try c.decode(String.self, forKey: .formula), inputs: inputs))
        case "check":
            self.init(id: id, label: label, kind: .check(
                formula: try c.decode(String.self, forKey: .formula), inputs: inputs, roll: try c.decodeIfPresent(String.self, forKey: .roll) ?? "check"
            ))
        case "resource": self.init(id: id, label: label, kind: .resource(try c.decode(String.self, forKey: .resource)))
        case "text": self.init(id: id, label: label, kind: .text(key: try c.decode(String.self, forKey: .key)))
        case "entries": self.init(id: id, label: label, kind: .entries(key: try c.decode(String.self, forKey: .key)))
        default: throw corrupt(decoder, "A row is “stat”, “check”, “resource”, “text” or “entries”.")
        }
    }
}

nonisolated extension SheetSection: Decodable {
    private enum CodingKeys: String, CodingKey { case id, title, rows }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.init(id: id, title: try c.decodeIfPresent(String.self, forKey: .title) ?? id, rows: try c.decode([SheetRow].self, forKey: .rows))
    }
}

nonisolated extension SheetLayout: Decodable {
    private enum CodingKeys: String, CodingKey { case sections }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sections: try c.decode([SheetSection].self, forKey: .sections))
    }
}
