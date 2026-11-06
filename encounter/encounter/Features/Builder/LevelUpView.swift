//
//  LevelUpView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A "Level Up" row on a playable character's page, which opens the sheet. Shown only when the character has a class
/// with a table to level from, and isn't at level 20 already.
struct LevelUpSection: View {
    let page: Page

    /// The level being taken, kept from when the sheet opened so the result isn't redrawn for the level after.
    @State private var levelling: LevelUpContext?

    var body: some View {
        Group {
            if let context = LevelUp.context(for: page) {
                Section {
                    Button("Level Up to \(context.needs.newLevel)…", systemImage: "arrow.up.circle") { levelling = context }
                }
            }
        }
        .sheet(isPresented: Binding(get: { levelling != nil }, set: { if !$0 { levelling = nil } })) {
            if let levelling {
                LevelUpView(context: levelling) { self.levelling = nil }
            }
        }
    }
}

/// The choices that come with the next level, then the result of taking it.
struct LevelUpView: View {
    let context: LevelUpContext
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var choices = LevelUpChoices()
    @State private var rolling = false
    @State private var rollText = ""
    @State private var takesFeat = false
    @State private var changes: [String] = []

    private var needs: LevelUpNeeds { context.needs }

    var body: some View {
        NavigationStack {
            Form {
                if changes.isEmpty { choicesForm } else { resultForm }
            }
            .formStyle(.grouped)
            .themedScreen()
            .themedRow()
            .navigationTitle("Level \(context.level) → \(needs.newLevel)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if changes.isEmpty { Button("Cancel", action: onClose) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if changes.isEmpty {
                        Button("Level Up", action: levelUp).disabled(!problems.isEmpty)
                    } else {
                        Button("Done", action: onClose)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var problems: [String] { context.problems(for: choices) }

    // MARK: Choices

    @ViewBuilder
    private var choicesForm: some View {
        hitPointsSection
        gainsSection
        if needs.choosesSubclass && !context.subclasses.isEmpty { subclassSection }
        if needs.hasImprovement { improvementSection }
        if context.cantripsToChoose > 0 { spellSection(title: String(localized: "Cantrips"), levels: [0], limit: context.cantripsToChoose, picks: \.cantrips) }
        if context.spellsToChoose > 0 {
            spellSection(title: String(localized: "Spells"), levels: Array(1...max(needs.highestSpellLevel, 1)), limit: context.spellsToChoose, picks: \.spells)
        }
        if !problems.isEmpty {
            Section {
                ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
            }
        }
    }

    private var hitPointsSection: some View {
        ThemedSection("Hit Points") {
            Picker("Gain", selection: $rolling) {
                Text("Average (\(LevelRules.averageRoll(hitDieSides: needs.hitDieSides)))").tag(false)
                Text("Roll d\(needs.hitDieSides)").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: rolling) { updateHitPoints() }
            if rolling {
                TextField("Result of the roll", text: $rollText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: rollText) { updateHitPoints() }
            }
            let constitution = context.scores[.constitution] ?? 10
            Text("Plus your Constitution modifier (\(CharacterRules.modifierText(for: constitution))), and at least 1 in all.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func updateHitPoints() {
        choices.hitPoints = rolling ? .rolled(Int(rollText) ?? 0) : .average
    }

    /// What the level gives that needs no choice.
    private var gainsSection: some View {
        ThemedSection("This Level Gives") {
            let bonus = CharacterRules.proficiencyBonus(atLevel: needs.newLevel)
            if bonus != CharacterRules.proficiencyBonus(atLevel: context.level) {
                Label("Proficiency bonus +\(bonus)", systemImage: "plus.circle")
            }
            let chosen = choices.subclass.flatMap { key in context.subclasses.first { $0.key == key } }
            ForEach(LevelUp.features(of: context, subclass: chosen, level: needs.newLevel), id: \.name) { feature in
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.name)
                    Text(feature.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            let slots = context.progression.slotsDescription(at: needs.newLevel)
            if !slots.isEmpty { Label("Spell slots: \(slots)", systemImage: "sparkles") }
        }
    }

    private var subclassSection: some View {
        ThemedSection("Subclass") {
            Picker("Subclass", selection: $choices.subclass) {
                Text("Choose…").tag(String?.none)
                ForEach(context.subclasses) { Text($0.name).tag(Optional($0.key)) }
            }
            if let key = choices.subclass, let chosen = context.subclasses.first(where: { $0.key == key }) {
                Text(chosen.summary).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
        }
    }

    // MARK: Ability Score Improvement

    private var improvementSection: some View {
        ThemedSection("Ability Score Improvement") {
            if !context.featOptions.isEmpty {
                Picker("Take", selection: $takesFeat) {
                    Text("Ability scores").tag(false)
                    Text("A feat").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: takesFeat) {
                    if takesFeat { choices.abilityIncreases = [:] } else { choices.feat = nil }
                }
            }
            if takesFeat {
                Picker("Feat", selection: $choices.feat) {
                    Text("Choose…").tag(String?.none)
                    ForEach(context.featOptions) { Text($0.name).tag(Optional($0.key)) }
                }
                if let key = choices.feat, let feat = context.featOptions.first(where: { $0.key == key }) {
                    if case .text(let prerequisite)? = feat.attributes["dnd5e.featPrerequisite"] {
                        Text("Prerequisite: \(prerequisite)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(feat.summary).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
            } else {
                Text("Raise one score by 2, or two scores by 1 each. No score goes above 20.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let spent = choices.abilityIncreases.values.reduce(0, +)
                ForEach(Ability.allCases) { ability in
                    let score = context.scores[ability] ?? 10
                    let points = choices.abilityIncreases[ability] ?? 0
                    Stepper(value: increase(ability), in: 0...2) {
                        HStack {
                            Text(ability.rawValue)
                            Spacer()
                            Text(points > 0 ? "\(score) → \(score + points)" : "\(score)")
                                .foregroundStyle(points > 0 ? Color.primary : Color.secondary)
                                .monospacedDigit()
                        }
                    }
                    .disabled(points == 0 && (spent >= 2 || score >= CharacterRules.maximumScore))
                }
            }
        }
    }

    private func increase(_ ability: Ability) -> Binding<Int> {
        Binding(
            get: { choices.abilityIncreases[ability] ?? 0 },
            set: { newValue in
                var points = choices.abilityIncreases
                points[ability] = newValue
                // Never more than 2 points in all: the other abilities give way to the one just raised.
                var others = points.filter { $0.key != ability && $0.value > 0 }.keys.sorted { $0.rawValue < $1.rawValue }
                while points.values.reduce(0, +) > 2, let drop = others.popLast() { points[drop] = max(0, (points[drop] ?? 0) - 1) }
                choices.abilityIncreases = points.filter { $0.value > 0 }
            }
        )
    }

    // MARK: Spells

    private func spellSection(title: String, levels: [Int], limit: Int, picks: WritableKeyPath<LevelUpChoices, Set<String>>) -> some View {
        Section {
            Text("Choose \(limit) — \(choices[keyPath: picks].count) chosen")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(levels, id: \.self) { level in
                let options = context.spellOptions(level: level)
                if !options.isEmpty {
                    DisclosureGroup(level == 0 ? String(localized: "Cantrips") : String(localized: "\(ClassProgression.ordinal(level)) level")) {
                        ForEach(options) { spell in
                            let isChosen = choices[keyPath: picks].contains(spell.key)
                            Toggle(isOn: Binding(
                                get: { isChosen },
                                set: { on in
                                    if on { choices[keyPath: picks].insert(spell.key) } else { choices[keyPath: picks].remove(spell.key) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(spell.name)
                                    Text(spell.spellHeadline).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!isChosen && choices[keyPath: picks].count >= limit)
                        }
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    // MARK: Taking the level

    private func levelUp() {
        changes = LevelUp.apply(choices, to: context, in: modelContext)
    }

    private var resultForm: some View {
        ThemedSection("Now Level \(needs.newLevel)") {
            ForEach(changes, id: \.self) { Label($0, systemImage: "checkmark.circle") }
        }
    }
}

#Preview("Wizard to level 2") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview", system: .dnd5e)
    world.edition = .srd51
    context.insert(world)
    let page = world.addPage(kind: .character, in: context)
    page.title = "Mira"
    page.characterRole = .playable
    page.summary = "Human Wizard, level 1"
    page.setReference(.library("srd51.class.wizard"), role: LinkRole.characterClass, in: context)
    page.setAttributeNumber("dnd5e.classLevel", 1)
    page.setAttributeNumber("dnd5e.hitPoints", 8)
    for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, 12) }
    return Group {
        if let levelling = LevelUp.context(for: page) {
            LevelUpView(context: levelling) {}
        }
    }
    .modelContainer(container)
}
