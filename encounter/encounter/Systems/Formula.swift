//
//  Formula.swift
//  encounter
//

import Foundation

/// A sum written as text, such as "floor((score - 10) / 2)", so a rule system can say how its numbers are worked out as data
/// rather than code. It has numbers, names (which can have dots, so "dnd5e.strength" is a name), + − * / and brackets, and the functions floor, ceil, round, abs, min and max.
nonisolated struct Formula: Equatable, Sendable {
    fileprivate indirect enum Node: Equatable, Sendable {
        case number(Double)
        /// A roll of dice, such as 1d4, which has a value only when something rolls it.
        case dice(count: Int, sides: Int)
        case variable(String)
        case negate(Node)
        case binary(Character, Node, Node)
        case call(String, [Node])
    }

    fileprivate let root: Node
    let text: String

    /// Reads a formula. Nil if it isn't one.
    init?(_ text: String) {
        var parser = FormulaParser(text)
        guard let root = parser.parse() else { return nil }
        self.root = root
        self.text = text
    }

    /// The names the formula uses.
    var variables: Set<String> {
        var found: Set<String> = []
        func visit(_ node: Node) {
            switch node {
            case .number, .dice: break
            case .variable(let name): found.insert(name)
            case .negate(let inner): visit(inner)
            case .binary(_, let left, let right): visit(left); visit(right)
            case .call(_, let arguments): arguments.forEach(visit)
            }
        }
        visit(root)
        return found
    }

    /// What the formula comes to, asking `value` for each name it uses. Nil if a name is unknown or it divides by zero.
    func evaluate(_ value: (String) -> Double?, dice: ((_ count: Int, _ sides: Int) -> Double)? = nil) -> Double? {
        Self.evaluate(root, value, dice)
    }

    /// Whether the formula rolls any dice, such as "1d4 + tier".
    var hasDice: Bool {
        func visit(_ node: Node) -> Bool {
            switch node {
            case .dice: true
            case .number, .variable: false
            case .negate(let inner): visit(inner)
            case .binary(_, let left, let right): visit(left) || visit(right)
            case .call(_, let arguments): arguments.contains(where: visit)
            }
        }
        return visit(root)
    }

    func evaluate(_ values: [String: Double]) -> Double? { evaluate { values[$0] } }

    private static func evaluate(_ node: Node, _ value: (String) -> Double?, _ dice: ((Int, Int) -> Double)?) -> Double? {
        switch node {
        case .number(let number): return number
        case .dice(let count, let sides): return dice?(count, sides)
        case .variable(let name): return value(name)
        case .negate(let inner): return evaluate(inner, value, dice).map { -$0 }
        case .binary(let op, let left, let right):
            guard let a = evaluate(left, value, dice), let b = evaluate(right, value, dice) else { return nil }
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            default: return b == 0 ? nil : a / b
            }
        case .call(let name, let arguments):
            var numbers: [Double] = []
            for argument in arguments {
                guard let number = evaluate(argument, value, dice) else { return nil }
                numbers.append(number)
            }
            switch (name, numbers.count) {
            case ("floor", 1): return numbers[0].rounded(.down)
            case ("ceil", 1): return numbers[0].rounded(.up)
            case ("round", 1): return numbers[0].rounded()
            case ("abs", 1): return abs(numbers[0])
            case ("min", 2...): return numbers.min()
            case ("max", 2...): return numbers.max()
            default: return nil
            }
        }
    }
}

/// Reads the text of a formula, by recursive descent: sums of products of signed things.
private nonisolated struct FormulaParser {
    enum Token: Equatable {
        case number(Double)
        case dice(count: Int, sides: Int)
        case name(String)
        case symbol(Character)
    }

    private var tokens: [Token] = []
    private var position = 0
    private var isValid = true

    init(_ text: String) {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isNumber || character == "." {
                var end = index
                while end < text.endIndex, text[end].isNumber || text[end] == "." { end = text.index(after: end) }
                // "1d4" or "d4": dice. A number followed straight away by a d and digits.
                var diceEnd = end
                if end < text.endIndex, text[end] == "d" || text[end] == "D" {
                    diceEnd = text.index(after: end)
                    while diceEnd < text.endIndex, text[diceEnd].isNumber { diceEnd = text.index(after: diceEnd) }
                }
                if diceEnd > end, text.index(after: end) < diceEnd, let count = Int(text[index..<end]), let sides = Int(text[text.index(after: end)..<diceEnd]),
                   count >= 1, sides >= 2 {
                    tokens.append(.dice(count: count, sides: sides))
                    index = diceEnd
                } else {
                    if let number = Double(text[index..<end]) { tokens.append(.number(number)) } else { isValid = false }
                    index = end
                }
            } else if character.isLetter || character == "_" {
                var end = index
                while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" || text[end] == "." { end = text.index(after: end) }
                let word = String(text[index..<end])
                if (word.first == "d" || word.first == "D"), word.count > 1, let sides = Int(word.dropFirst()), sides >= 2 {
                    tokens.append(.dice(count: 1, sides: sides))
                } else {
                    tokens.append(.name(word))
                }
                index = end
            } else if "+-*/(),".contains(character) {
                tokens.append(.symbol(character))
                index = text.index(after: index)
            } else if character == "−" {
                // The minus sign the app prints.
                tokens.append(.symbol("-"))
                index = text.index(after: index)
            } else {
                isValid = false
                return
            }
        }
    }

    mutating func parse() -> Formula.Node? {
        guard isValid, !tokens.isEmpty, let node = sum(), position == tokens.count else { return nil }
        return node
    }

    private func peek() -> Token? { position < tokens.count ? tokens[position] : nil }

    private mutating func accept(_ symbol: Character) -> Bool {
        guard peek() == .symbol(symbol) else { return false }
        position += 1
        return true
    }

    private mutating func sum() -> Formula.Node? {
        guard var left = product() else { return nil }
        while let token = peek(), case .symbol(let op) = token, op == "+" || op == "-" {
            position += 1
            guard let right = product() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func product() -> Formula.Node? {
        guard var left = signed() else { return nil }
        while let token = peek(), case .symbol(let op) = token, op == "*" || op == "/" {
            position += 1
            guard let right = signed() else { return nil }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func signed() -> Formula.Node? {
        if accept("-") { return signed().map { .negate($0) } }
        if accept("+") { return signed() }
        return atom()
    }

    private mutating func atom() -> Formula.Node? {
        guard let token = peek() else { return nil }
        position += 1
        switch token {
        case .number(let number):
            return .number(number)
        case .dice(let count, let sides):
            return .dice(count: count, sides: sides)
        case .name(let name):
            guard accept("(") else { return .variable(name) }
            var arguments: [Formula.Node] = []
            if !accept(")") {
                repeat {
                    guard let argument = sum() else { return nil }
                    arguments.append(argument)
                } while accept(",")
                guard accept(")") else { return nil }
            }
            return .call(name, arguments)
        case .symbol("("):
            guard let inner = sum(), accept(")") else { return nil }
            return inner
        case .symbol:
            return nil
        }
    }
}

/// The named formulas of a rule system. One can use another by its name, so "spellSaveDC" can be "8 + proficiencyBonus +
/// abilityModifier"; the numbers that start it off, such as the level or an ability score, are given when it is worked out.
nonisolated struct FormulaSet: Sendable {
    private var formulas: [String: Formula] = [:]

    /// The formulas by name. Any that can't be read are left out.
    init(_ definitions: [String: String]) {
        for (name, text) in definitions {
            if let formula = Formula(text) { formulas[name] = formula }
        }
    }

    var names: Set<String> { Set(formulas.keys) }

    func formula(_ name: String) -> Formula? { formulas[name] }

    /// What a formula comes to, given the numbers it starts from (which win over a formula of the same name). Nil if it has
    /// no such formula, uses a name that is neither given nor a formula, or goes round in a circle.
    func value(_ name: String, _ inputs: [String: Double] = [:], dice: ((_ count: Int, _ sides: Int) -> Double)? = nil) -> Double? {
        resolve(name, inputs, dice, depth: 0)
    }

    /// The same, as a whole number.
    func integer(_ name: String, _ inputs: [String: Double] = [:]) -> Int? {
        value(name, inputs).map { Int($0.rounded()) }
    }

    private func resolve(_ name: String, _ inputs: [String: Double], _ dice: ((Int, Int) -> Double)?, depth: Int) -> Double? {
        if let given = inputs[name] { return given }
        guard depth < 16, let formula = formulas[name] else { return nil }
        return formula.evaluate({ resolve($0, inputs, dice, depth: depth + 1) }, dice: dice)
    }
}
