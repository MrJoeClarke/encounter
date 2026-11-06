//
//  GenericRollSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Rolls a check by the system's own roll model and says what it came to: every die, what is added, and how the result reads.
struct GenericRollSheet: View {
    let page: Page
    let system: any RuleSystem
    let label: String
    let modifier: Int
    let roll: String

    @Environment(\.dismiss) private var dismiss
    @State private var mode = AdvantageMode.normal
    @State private var hasDifficulty = true
    @State private var difficulty = 12
    @State private var result: CheckResult?
    @State private var gained = false

    private var model: RollModel? { system.rollModel }
    private var conditions: RollConditionEffect { GenericConditionsBox.effect(on: roll, page: page, system: system) }

    var body: some View {
        NavigationStack {
            Form {
                if let model {
                    Section {
                        LabeledContent("Modifier", value: GenericSheetView.signed(modifier + conditions.penalty))
                        Picker("Advantage", selection: $mode) {
                            Text("None").tag(AdvantageMode.normal)
                            Text("Advantage").tag(AdvantageMode.advantage)
                            Text("Disadvantage").tag(AdvantageMode.disadvantage)
                        }
                        Toggle("Against a difficulty", isOn: $hasDifficulty)
                        if hasDifficulty { Stepper("Difficulty \(difficulty)", value: $difficulty, in: 1...40) }
                        ForEach(conditions.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
                    }
                    Section {
                        Button { rollNow(model) } label: {
                            Label("Roll", systemImage: "dice").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    if let result { resultSection(result, model: model) }
                } else {
                    ContentUnavailableView("No Dice", systemImage: "dice", description: Text("This system has no roll model."))
                }
            }
            .formStyle(.grouped)
            .themedScreen()
            .themedRow()
            .navigationTitle(label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { mode = conditions.mode }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func rollNow(_ model: RollModel) {
        gained = false
        result = CheckRoller.roll(model, modifier: modifier + conditions.penalty, mode: mode, target: hasDifficulty ? difficulty : nil)
    }

    @ViewBuilder
    private func resultSection(_ result: CheckResult, model: RollModel) -> some View {
        ThemedSection("Result") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(Array(zip(model.dice, result.dice)), id: \.0.name) { die, value in
                    VStack {
                        Text("\(value)").font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text(die.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                if result.bonusDie != 0 {
                    VStack {
                        Text(GenericSheetView.signed(result.bonusDie)).font(.title2).monospacedDigit()
                        Text(result.bonusDie > 0 ? "Advantage" : "Disadvantage").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Total", value: result.total.formatted())
            Text(summary(result, model: model)).font(.headline)
            // The die that showed more can give the roller something back, such as a Hope.
            if let name = result.higherDie, let die = model.dice.first(where: { $0.name == name }), let resource = die.gains {
                if let definition = system.resources.first(where: { $0.id == resource }) {
                    Button(gained ? "\(definition.name) gained" : "Gain 1 \(definition.name)", systemImage: "plus.circle") {
                        SheetEngine.adjust(resource, by: 1, on: page, system: system)
                        gained = true
                    }
                    .disabled(gained)
                } else if let definition = system.worldResources.first(where: { $0.id == resource }), let world = page.world {
                    Button(gained ? "\(definition.name) gained" : "The GM gains 1 \(definition.name)", systemImage: "plus.circle") {
                        SheetEngine.adjustWorld(resource, by: 1, on: world, system: system)
                        gained = true
                    }
                    .disabled(gained)
                }
            }
        }
    }

    /// "Critical success", or "Success with Hope", or "Failure with Fear", as the roll model reads it.
    private func summary(_ result: CheckResult, model: RollModel) -> String {
        var parts: [String] = []
        if result.isCritical { parts.append(String(localized: "Critical success")) }
        else if let meets = result.meetsTarget { parts.append(meets ? String(localized: "Success") : String(localized: "Failure")) }
        if !result.isCritical, let higher = result.higherDie { parts.append(String(localized: "with \(higher)")) }
        return parts.isEmpty ? String(localized: "Rolled") : parts.joined(separator: " ")
    }
}

#Preview("Daggerheart roll") {
    let data = GenericPreviewData.make()
    return Group {
        if let data {
            GenericRollSheet(page: data.character, system: RuleSystems.system(forKey: "daggerheart"), label: "Agility", modifier: 2, roll: "check")
                .modelContainer(data.container)
        }
    }
}
