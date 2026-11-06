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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var restWithMoves: RestDefinition?

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
                    if let world = page.world, !system.worldResources.isEmpty { worldResources(world) }
                    ForEach(sections) { section in
                        card(section)
                    }
                    if page.world?.rules.contains(.conditions) == true, !system.conditions.isEmpty {
                        GenericConditionsBox(page: page, system: system)
                    }
                }
                .padding()
            }
            .themedBackground(inksText: true)
            // The Character menu can take a rest or level up.
            .focusedSceneValue(\.sheetActions, SheetActions(
                rests: system.rests.map { rest in SheetActions.Rest(name: rest.name) { takeRest(rest) } },
                levelUp: system.advancement.flatMap { Advancement.canLevelUp(page, rule: $0) ? { isLevellingUp = true } : nil }
            ))
            .sheet(item: $rolling) { request in
                GenericRollSheet(page: page, system: system, label: request.label, modifier: request.modifier, roll: request.roll)
            }
            .sheet(isPresented: $isLevellingUp) { GenericLevelUpView(page: page) { isLevellingUp = false } }
            .sheet(item: $restWithMoves) { rest in GenericRestSheet(page: page, rest: rest) }
            .alert("Rest", isPresented: Binding(get: { restMessage != nil }, set: { if !$0 { restMessage = nil } })) {
                Button("OK") {}
            } message: { Text(restMessage ?? "") }
        } else {
            ContentUnavailableView("No Sheet", systemImage: "doc.text", description: Text("This system has no character sheet."))
        }
    }

    // MARK: Header

    private var level: Int? { system.advancement.map { Advancement.level(of: page, rule: $0) } }

    /// Side by side, or stacked when the text is large and would otherwise break in the middle of words.
    private var adaptive: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    private var header: some View {
        adaptive {
            VStack(alignment: .leading) {
                Text(page.title.isEmpty ? String(localized: "Untitled") : page.title).font(.largeTitle.weight(.semibold))
                Text([page.summary, level.map { String(localized: "Level \($0)") }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            HStack {
                Menu("Rest", systemImage: "bed.double") {
                    ForEach(system.rests) { rest in Button(rest.name) { takeRest(rest) } }
                }
                if let rule = system.advancement, Advancement.canLevelUp(page, rule: rule) {
                    Button("Level Up", systemImage: "arrow.up.circle") { isLevellingUp = true }
                }
            }
            // In a narrow window the name gives way, not the words on the buttons.
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// What the whole world shares, such as the GM's Fear.
    private func worldResources(_ world: World) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(system.worldResources) { resource in
                let value = SheetEngine.worldValue(resource, world: world, system: system)
                adaptive {
                    VStack(alignment: .leading) {
                        Text(resource.name).font(.headline)
                        Text("shared by the whole table").font(.caption).foregroundStyle(.secondary)
                    }
                    if !typeSize.isAccessibilitySize { Spacer() }
                    HStack {
                        Text("\(value.current)\(value.maximum.map { " of \($0)" } ?? "")").monospacedDigit().foregroundStyle(.secondary)
                        Button { SheetEngine.adjustWorld(resource.id, by: -1, on: world, system: system) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Spend one \(resource.name)")
                        Button { SheetEngine.adjustWorld(resource.id, by: 1, on: world, system: system) } label: { Image(systemName: "plus.circle") }
                            .accessibilityLabel("Add one \(resource.name)")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedSheetPanel()
    }

    // MARK: Rows

    private func card(_ section: SheetSectionValue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.section.title).themedTitle(.headline)
            OrnamentalRule()
            ForEach(section.rows) { row in
                rowView(row)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedSheetPanel()
    }

    @ViewBuilder
    private func rowView(_ row: SheetRowValue) -> some View {
        switch row.value {
        case .number(let number):
            HStack {
                Text(row.row.label)
                Spacer()
                Text(number.formatted()).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .check(let modifier, let roll):
            Button { rolling = RollRequest(label: row.row.label, modifier: modifier, roll: roll) } label: {
                HStack {
                    Text(row.row.label)
                    Spacer()
                    Text(Self.signed(modifier)).monospacedDigit().foregroundStyle(.tint)
                    Image(systemName: "dice").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(row.row.label), \(Self.signed(modifier))")
            .accessibilityHint("Rolls a check")
            .buttonStyle(.plain)
        case .resource(let current, let maximum):
            if case .resource(let id) = row.row.kind, let resource = system.resources.first(where: { $0.id == id }) {
                resourceRow(resource, label: row.row.label, current: current, maximum: maximum)
            }
        case .text(let text):
            if !text.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.row.label)
                    Spacer()
                    Text(text).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
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
        let summary = marksSpent ? "\(filled) marked of \(maximum ?? 0)" : "\(current)\(maximum.map { " of \($0)" } ?? "")"
        return adaptive {
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
                    .accessibilityHidden(true)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            HStack {
                Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                // A spent resource is marked by using some of what remains, and a remaining one is spent the same way.
                Button { SheetEngine.adjust(resource.id, by: marksSpent ? 1 : -1, on: page, system: system) } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel(marksSpent ? "Clear one \(label)" : "Spend one \(label)")
                Button { SheetEngine.adjust(resource.id, by: marksSpent ? -1 : 1, on: page, system: system) } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel(marksSpent ? "Mark one \(label)" : "Gain one \(label)")
            }
        }
        .accessibilityElement(children: .contain)
        .buttonStyle(.borderless)
    }

    static func signed(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    // MARK: Resting

    /// Takes a rest: a rest with moves asks which, and one without gives back what the resources say.
    private func takeRest(_ rest: RestDefinition) {
        if !rest.moves.isEmpty { restWithMoves = rest; return }
        let lines = RestEngine.take(rest, moves: [], on: page, system: system, dice: Self.rollDice) ?? []
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
            Text("Conditions").themedTitle(.headline)
            OrnamentalRule()
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
        .themedSheetPanel()
    }
}

extension GenericConditionsBox {
    /// What the character's conditions do to a kind of roll.
    static func effect(on roll: String, page: Page, system: any RuleSystem) -> RollConditionEffect {
        let ids = Set(page.attributeText("\(system.key).conditions").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return ConditionEngine.effect(on: roll, active: Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) }), definitions: system.conditions, formulas: system.formulas)
    }
}

#Preview("Daggerheart sheet") {
    let data = GenericPreviewData.make()
    return Group { if let data { GenericSheetView(page: data.character).modelContainer(data.container) } }
        #if os(macOS)
        .frame(width: 900, height: 900)
        #endif
}

#if DEBUG
#Preview("Daggerheart sheet, Slide Over strip (320)") {
    let data = GenericPreviewData.make()
    return NavigationStack { if let data { GenericSheetView(page: data.character).modelContainer(data.container) } }
        .inWindow(.strip, height: 900)
}

#Preview("Daggerheart sheet, half screen (507)") {
    let data = GenericPreviewData.make()
    return NavigationStack { if let data { GenericSheetView(page: data.character).modelContainer(data.container) } }
        .inWindow(.half, height: 900)
}
#endif
