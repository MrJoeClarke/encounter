//
//  ActionCardView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// What to roll for one action on the sheet, and with Roll buttons (if they are on) the roll itself. A spell also
/// offers the slots to cast it with, and casting spends one.
struct ActionCardView: View {
    let page: Page
    let action: SheetAction
    let rollsInApp: Bool
    let log: RollLog
    let onClose: () -> Void

    @State private var results: [String: RollResult] = [:]
    @State private var mode = AdvantageMode.normal
    @State private var isCritical = false
    @State private var slotLevel: Int?
    @State private var castMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let sheet = CharacterSheet(page: page), let card = card(in: sheet) {
                    Form {
                        content(card, sheet: sheet)
                    }
                    .formStyle(.grouped)
                    .navigationTitle(card.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                } else {
                    ContentUnavailableView("Nothing to Show", systemImage: "questionmark.circle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
        .onAppear { startWithConditions() }
    }

    /// A roll made under a condition starts as it should be made: with advantage or disadvantage if one gives it.
    private func startWithConditions() {
        guard let sheet = CharacterSheet(page: page), let card = card(in: sheet),
              let first = card.rolls.first(where: { $0.allowsAdvantage && $0.defaultMode != .normal }) else { return }
        mode = first.defaultMode
    }

    // MARK: The card

    private func card(in sheet: CharacterSheet) -> ActionCard? {
        switch action {
        case .ability(let ability): sheet.card(forAbility: ability)
        case .save(let ability): sheet.saves.first { $0.ability == ability }.map { sheet.card(for: $0) }
        case .skill(let name): sheet.skills.first { $0.name == name }.map { sheet.card(for: $0) }
        case .initiative: sheet.initiativeCard
        case .deathSave: sheet.deathSaveCard
        case .attack(let name): sheet.attacks.first { $0.weapon.name == name }.map { sheet.card(for: $0) }
        case .spell(let name):
            sheet.spells.first { $0.name == name }.map { spell in
                // The slot picked, or else the lowest one left, which is what the Cast button will use.
                let levels = sheet.castableSlotLevels(for: spell)
                return sheet.card(for: spell, slotLevel: slotLevel.flatMap { levels.contains($0) ? $0 : nil } ?? levels.first)
            }
        }
    }

    @ViewBuilder
    private func content(_ card: ActionCard, sheet: CharacterSheet) -> some View {
        if !card.subtitle.isEmpty {
            Section { Text(card.subtitle).foregroundStyle(.secondary) }
        }
        if case .spell(let name) = action, let spell = sheet.spells.first(where: { $0.name == name }) {
            castSection(spell, sheet: sheet)
        }
        if !card.rolls.isEmpty {
            Section("Rolls") {
                if rollsInApp, card.rolls.contains(where: { $0.kind == .attack }) || card.rolls.contains(where: \.allowsAdvantage) {
                    Picker("Roll with", selection: $mode) {
                        Text("Normal").tag(AdvantageMode.normal)
                        Text("Advantage").tag(AdvantageMode.advantage)
                        Text("Disadvantage").tag(AdvantageMode.disadvantage)
                    }
                    .pickerStyle(.segmented)
                }
                if rollsInApp, card.rolls.contains(where: { $0.kind == .attack }), card.rolls.contains(where: { $0.kind == .damage }) {
                    Toggle("Critical hit (double the damage dice)", isOn: $isCritical)
                }
                ForEach(card.rolls) { roll in rollRow(roll, sheet: sheet) }
            }
        }
        if case .deathSave = action { deathSaveSection(sheet) }
        if !card.notes.isEmpty {
            Section { ForEach(card.notes, id: \.self) { Text($0).font(.callout) } }
        }
        if !card.text.isEmpty {
            Section("Description") { Text(card.text).font(.callout) }
        }
    }

    // MARK: Rolls

    private func rollRow(_ roll: ActionRoll, sheet: CharacterSheet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(roll.title).font(.headline)
                    Text(roll.instruction).font(.title3.monospacedDigit())
                    if !roll.addedFrom.isEmpty { Text(roll.addedFrom).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if rollsInApp {
                    if roll.autoFail == nil {
                        Button("Roll", systemImage: "dice") { perform(roll, sheet: sheet) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            if let autoFail = roll.autoFail {
                Label(autoFail, systemImage: "xmark.circle").font(.callout).foregroundStyle(.red)
            }
            ForEach(roll.conditionNotes, id: \.self) { line in
                Label(line, systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(.orange)
            }
            if let note = roll.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if let result = results[roll.id] {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(result.total)").font(.system(size: 34, weight: .bold)).monospacedDigit()
                    Text(result.breakdown).font(.callout).foregroundStyle(.secondary)
                    if result.isNaturalTwenty { Label("Natural 20", systemImage: "sparkles").foregroundStyle(.orange) }
                    if result.isNaturalOne { Label("Natural 1", systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                if roll.kind == .healing {
                    Button("Heal \(result.total) Hit Points") { sheet.heal(result.total) }.buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func perform(_ roll: ActionRoll, sheet: CharacterSheet) {
        let attacks = roll.kind == .attack
        let result = DiceRoller.roll(
            roll.dice, mode: roll.allowsAdvantage ? mode : .normal, critical: roll.kind == .damage && isCritical
        )
        results[roll.id] = result
        log.add(title: roll.title, result: result)
        // A death saving throw rolled here is recorded as well.
        if case .deathSave = action { record(sheet.recordDeathSave(roll: result.total)) }
        // A natural 20 on an attack makes the damage rolled next a critical hit, and a natural 1 undoes it.
        if attacks { isCritical = result.isNaturalTwenty }
    }

    // MARK: Death saves

    @State private var rolledOnTable = ""
    @State private var deathSaveMessage: String?

    private func record(_ outcome: CharacterSheet.DeathSaveOutcome) {
        switch outcome {
        case .success: deathSaveMessage = String(localized: "Success recorded.")
        case .failure: deathSaveMessage = String(localized: "Failure recorded.")
        case .doubleFailure: deathSaveMessage = String(localized: "A 1: two failures recorded.")
        case .revived: deathSaveMessage = String(localized: "A 20: back on your feet with 1 hit point.")
        }
    }

    /// For a roll made with real dice: type what the die showed and the right marks are made.
    @ViewBuilder
    private func deathSaveSection(_ sheet: CharacterSheet) -> some View {
        Section("Record") {
            if !rollsInApp {
                HStack {
                    TextField("What the die showed", text: $rolledOnTable)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("Record") {
                        if let value = Int(rolledOnTable), (1...20).contains(value) {
                            record(sheet.recordDeathSave(roll: value))
                            rolledOnTable = ""
                        }
                    }
                    .disabled(Int(rolledOnTable).map { !(1...20).contains($0) } ?? true)
                }
            }
            Text("Successes \(sheet.deathSaveSuccesses) of 3 · Failures \(sheet.deathSaveFailures) of 3")
            if sheet.isDead { Label("Dead", systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
            if sheet.isStable { Label("Stable", systemImage: "heart.circle").foregroundStyle(.green) }
            if let deathSaveMessage { Label(deathSaveMessage, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
        }
    }

    // MARK: Casting

    @ViewBuilder
    private func castSection(_ spell: SheetSpell, sheet: CharacterSheet) -> some View {
        if spell.level > 0 {
            Section("Cast") {
                let levels = sheet.castableSlotLevels(for: spell)
                if levels.isEmpty && !spell.isRitual {
                    Label("No spell slots left for this spell.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                } else if !levels.isEmpty {
                    Picker("Spell slot", selection: Binding(get: { slotLevel ?? levels[0] }, set: { slotLevel = $0 })) {
                        ForEach(levels, id: \.self) { level in
                            Text("\(ClassProgression.ordinal(level)) level — \(sheet.slotsRemaining[level - 1]) left").tag(level)
                        }
                    }
                    Button("Cast, Using a Slot", systemImage: "wand.and.stars") {
                        let chosen = slotLevel ?? levels[0]
                        if sheet.cast(spell, slotLevel: chosen) {
                            slotLevel = sheet.slotsRemaining[chosen - 1] > 0 ? chosen : nil
                            castMessage = String(localized: "Cast with a \(ClassProgression.ordinal(chosen))-level slot.")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if spell.isRitual {
                    Button("Cast as a Ritual, No Slot", systemImage: "book") {
                        if sheet.cast(spell, slotLevel: nil) { castMessage = String(localized: "Cast as a ritual. This takes 10 minutes longer.") }
                    }
                }
                if let castMessage { Label(castMessage, systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
        }
    }
}

#Preview("Fireball, rolling on") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview", system: .dnd5e)
    world.edition = .srd51
    context.insert(world)
    let page = world.addPage(kind: .character, in: context)
    page.title = "Mira Vale"
    page.setReference(.library("srd51.class.wizard"), role: LinkRole.characterClass, in: context)
    page.setAttributeNumber("dnd5e.classLevel", 5)
    page.setAttributeNumber("dnd5e.hitPoints", 28)
    page.setAttributeNumber("dnd5e.proficiencyBonus", 3)
    page.setAttributeNumber("dnd5e.intelligence", 17)
    page.attributes["dnd5e.spells"] = .entries([EntryValue(name: "Fireball"), EntryValue(name: "Fire Bolt")])
    return ActionCardView(page: page, action: .spell("Fireball"), rollsInApp: true, log: RollLog()) {}
        .modelContainer(container)
        .frame(width: 520, height: 760)
}
