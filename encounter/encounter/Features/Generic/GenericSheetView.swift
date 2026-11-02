//
//  GenericSheetView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A character's sheet for any system that describes its sheet as data (see `SheetLayout`): the rows the system lists, worked
/// out from the character, with what is played (hit points, Hope, stress) written back to the character.
struct GenericSheetView: View {
    let page: Page

    @State private var rolling: RollRequest?
    @State private var isLevellingUp = false
    @State private var restMessage: String?

    private struct RollRequest: Identifiable {
        let id = UUID()
        let label: String
        let modifier: Int
        let roll: String
    }

    private var system: any RuleSystem { RuleSystems.system(forKey: page.world?.systemRaw ?? "") }

    var body: some View {
        if let layout = system.sheetLayout {
            let sections = SheetEngine.build(layout, for: page, system: system)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(sections) { section in
                        card(section)
                    }
                    if page.world?.rules.contains(.conditions) == true, !system.conditions.isEmpty {
                        GenericConditionsBox(page: page, system: system)
                    }
                }
                .padding()
            }
            .sheet(item: $rolling) { request in
                GenericRollSheet(page: page, system: system, label: request.label, modifier: request.modifier, roll: request.roll)
            }
            .sheet(isPresented: $isLevellingUp) { GenericLevelUpView(page: page) { isLevellingUp = false } }
            .alert("Rest", isPresented: Binding(get: { restMessage != nil }, set: { if !$0 { restMessage = nil } })) {
                Button("OK") {}
            } message: { Text(restMessage ?? "") }
        } else {
            ContentUnavailableView("No Sheet", systemImage: "doc.text", description: Text("This system has no character sheet."))
        }
    }

    // MARK: Header

    private var level: Int? { system.advancement.map { Advancement.level(of: page, rule: $0) } }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(page.title.isEmpty ? String(localized: "Untitled") : page.title).font(.largeTitle.weight(.semibold))
                Text([page.summary, level.map { String(localized: "Level \($0)") }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Rest", systemImage: "bed.double") {
                ForEach(system.rests) { rest in Button(rest.name) { takeRest(rest) } }
            }
            if let rule = system.advancement, Advancement.canLevelUp(page, rule: rule) {
                Button("Level Up", systemImage: "arrow.up.circle") { isLevellingUp = true }
            }
        }
    }

    // MARK: Rows

    private func card(_ section: SheetSectionValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.section.title).font(.headline)
            ForEach(section.rows) { row in
                rowView(row)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func rowView(_ row: SheetRowValue) -> some View {
        switch row.value {
        case .number(let number):
            LabeledContent(row.row.label, value: number.formatted())
        case .check(let modifier, let roll):
            Button { rolling = RollRequest(label: row.row.label, modifier: modifier, roll: roll) } label: {
                HStack {
                    Text(row.row.label)
                    Spacer()
                    Text(Self.signed(modifier)).monospacedDigit().foregroundStyle(.tint)
                    Image(systemName: "dice").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .resource(let current, let maximum):
            if case .resource(let id) = row.row.kind, let resource = system.resources.first(where: { $0.id == id }) {
                resourceRow(resource, label: row.row.label, current: current, maximum: maximum)
            }
        case .text(let text):
            if !text.isEmpty { LabeledContent(row.row.label, value: text) }
        case .entries(let entries):
            if entries.isEmpty {
                Text("None yet. Add them in the page.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.subheadline.weight(.semibold))
                    if !entry.text.isEmpty { Text(entry.text).font(.callout).foregroundStyle(.secondary) }
                }
            }
        case .unknown:
            LabeledContent(row.row.label, value: "—")
        }
    }

    /// A resource as a row of slots with buttons to spend and gain. What the page keeps as spent shows as marked.
    private func resourceRow(_ resource: ResourceDefinition, label: String, current: Int, maximum: Int?) -> some View {
        let marksSpent = resource.storage == .spent
        let filled = marksSpent ? (maximum ?? 0) - current : current
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                if let maximum, maximum > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(maximum, 14), id: \.self) { index in
                            Circle().fill(index < filled ? Color.accentColor : Color.clear)
                                .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            Spacer()
            Text(marksSpent ? "\(filled) marked of \(maximum ?? 0)" : "\(current)\(maximum.map { " of \($0)" } ?? "")")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            // A spent resource is marked by using some of what remains, and a remaining one is spent the same way.
            Button { SheetEngine.adjust(resource.id, by: marksSpent ? 1 : -1, on: page, system: system) } label: { Image(systemName: "minus.circle") }
            Button { SheetEngine.adjust(resource.id, by: marksSpent ? -1 : 1, on: page, system: system) } label: { Image(systemName: "plus.circle") }
        }
        .buttonStyle(.borderless)
    }

    static func signed(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    // MARK: Resting

    /// Gives back what a kind of rest gives back, as the system says, rolling any dice in the amounts.
    private func takeRest(_ rest: RestDefinition) {
        let inputs = SheetEngine.inputs(for: page, advancement: system.advancement)
        var lines: [String] = []
        for resource in system.resources {
            let before = page.attributeNumber(resource.key)
            guard let value = ResourceRules.valueAfter(
                rest: rest.id, resource: resource, current: before, formulas: system.formulas, inputs: inputs, dice: Self.rollDice
            ) else { continue }
            page.setAttributeNumber(resource.key, value)
            let change = Int(value - (before ?? 0))
            if change != 0 { lines.append("\(resource.name): \(change > 0 ? "+" : "−")\(abs(change))") }
        }
        restMessage = lines.isEmpty ? String(localized: "Nothing to restore.") : "\(rest.name)\n" + lines.joined(separator: "\n")
    }

    static func rollDice(_ count: Int, _ sides: Int) -> Double {
        Double((0..<count).reduce(0) { total, _ in total + Int.random(in: 1...sides) })
    }
}

// MARK: Conditions

/// The conditions a system lists, to switch on and off for the character.
struct GenericConditionsBox: View {
    let page: Page
    let system: any RuleSystem

    private var key: String { "\(system.key).conditions" }

    private var active: Set<String> {
        Set(page.attributeText(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions").font(.headline)
            ForEach(system.conditions) { condition in
                Toggle(condition.name, isOn: Binding(
                    get: { active.contains(condition.id) },
                    set: { isOn in
                        var ids = active
                        if isOn { ids.insert(condition.id) } else { ids.remove(condition.id) }
                        page.setAttributeText(key, system.conditions.map(\.id).filter(ids.contains).joined(separator: ", "))
                    }
                ))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension GenericConditionsBox {
    /// What the character's conditions do to a kind of roll.
    static func effect(on roll: String, page: Page, system: any RuleSystem) -> RollConditionEffect {
        let ids = Set(page.attributeText("\(system.key).conditions").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return ConditionEngine.effect(on: roll, active: Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) }), definitions: system.conditions, formulas: system.formulas)
    }
}
