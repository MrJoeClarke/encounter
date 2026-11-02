//
//  GenericLevelUpView.swift
//  encounter
//

import SwiftUI

/// The place in a character's page to level up, for a system that describes levelling as data.
struct GenericLevelUpSection: View {
    let page: Page
    @State private var isLevellingUp = false

    var body: some View {
        if let rule = RuleSystems.system(forKey: page.world?.systemRaw ?? "").advancement, Advancement.canLevelUp(page, rule: rule) {
            Section {
                Button("Level Up to \(Advancement.level(of: page, rule: rule) + 1)…", systemImage: "arrow.up.circle") { isLevellingUp = true }
            }
            .sheet(isPresented: $isLevellingUp) { GenericLevelUpView(page: page) { isLevellingUp = false } }
        }
    }
}

/// The picks that come with the next level, then what taking it changed.
struct GenericLevelUpView: View {
    let page: Page
    let onClose: () -> Void

    @State private var picks: [String: Int] = [:]
    @State private var changes: [String]?

    private var system: any RuleSystem { RuleSystems.system(forKey: page.world?.systemRaw ?? "") }
    private var rule: AdvancementRule? { system.advancement }

    private var spent: Int {
        picks.reduce(0) { total, pick in total + pick.value * (rule?.choices.first { $0.id == pick.key }?.cost ?? 0) }
    }
    private var remaining: Int { (rule?.choicePoints ?? 0) - spent }

    var body: some View {
        NavigationStack {
            Form {
                if let rule {
                    if let changes { resultSection(changes) } else { choicesSection(rule) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(rule.map { "Level \(Advancement.level(of: page, rule: $0) + (changes == nil ? 1 : 0))" } ?? "Level Up")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if changes == nil { Button("Cancel", action: onClose) } }
                ToolbarItem(placement: .confirmationAction) {
                    if changes == nil { Button("Level Up", action: levelUp).disabled(remaining != 0) } else { Button("Done", action: onClose) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private func choicesSection(_ rule: AdvancementRule) -> some View {
        if rule.choicePoints > 0 {
            Section {
                ForEach(rule.choices) { choice in
                    Stepper(value: Binding(get: { picks[choice.id] ?? 0 }, set: { picks[choice.id] = $0 }), in: 0...((picks[choice.id] ?? 0) + (remaining >= choice.cost ? remaining / choice.cost : 0))) {
                        HStack {
                            Text(choice.title)
                            Spacer()
                            Text("\(picks[choice.id] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Choose how to spend \(rule.choicePoints) points")
            } footer: {
                Text(remaining == 0 ? "All points spent." : "\(remaining) to spend.")
            }
        } else {
            Section { Text("This level has no choices to make.") }
        }
    }

    private func resultSection(_ changes: [String]) -> some View {
        Section("What changed") {
            if changes.isEmpty { Text("Nothing else changed.") }
            ForEach(changes, id: \.self) { Text($0) }
        }
    }

    private func levelUp() {
        guard let rule else { return }
        let ids = picks.sorted { $0.key < $1.key }.flatMap { Array(repeating: $0.key, count: $0.value) }
        guard let result = Advancement.levelUp(page, rule: rule, formulas: system.formulas, picks: ids) else { return }
        let labels = Dictionary(uniqueKeysWithValues: system.attributes.map { ($0.key, String(localized: $0.label)) })
        changes = result.map { "\(labels[$0.key] ?? $0.key): \(Int($0.from)) → \(Int($0.to))" }
    }
}
