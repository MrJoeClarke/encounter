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

    /// How many of each choice are picked.
    @State private var counts: [String: Int] = [:]
    /// What the player said for each pick, by "choice id#which one" (and by choice id alone for what is always taken).
    @State private var selections: [String: [String]] = [:]
    @State private var result: LevelUpResult?

    private var system: any RuleSystem { RuleSystems.system(forKey: page.world?.systemRaw ?? "") }
    private var rule: AdvancementRule? { system.advancement }
    private var newLevel: Int { rule.map { Advancement.level(of: page, rule: $0) + 1 } ?? 1 }

    private var spent: Int {
        counts.reduce(0) { total, pick in total + pick.value * (rule?.choices.first { $0.id == pick.key }?.cost ?? 0) }
    }
    private var remaining: Int { (rule?.choicePoints ?? 0) - spent }

    /// The picks as they stand.
    private var picks: [LevelUpPick] {
        guard let rule else { return [] }
        return rule.choices.flatMap { choice in
            (0..<(counts[choice.id] ?? 0)).map { LevelUpPick(id: choice.id, selections: selections["\(choice.id)#\($0)"] ?? []) }
        }
    }

    private var requiredSelections: [String: [String]] {
        Dictionary(uniqueKeysWithValues: (rule?.required(onLevel: newLevel) ?? []).map { ($0.id, selections[$0.id] ?? []) })
    }

    private var isReady: Bool {
        guard let rule, remaining == 0 else { return false }
        let picksReady = picks.allSatisfy { pick in
            rule.choices.first { $0.id == pick.id }.map { Advancement.isComplete(pick, choice: $0, on: page, level: newLevel, system: system) } ?? false
        }
        let requiredReady = rule.required(onLevel: newLevel).allSatisfy {
            Advancement.isComplete(LevelUpPick(id: $0.id, selections: selections[$0.id] ?? []), choice: $0, on: page, level: newLevel, system: system)
        }
        return picksReady && requiredReady
    }

    var body: some View {
        NavigationStack {
            Form {
                if let rule {
                    if let result { resultSection(result) } else { choicesSections(rule) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Level \(result == nil ? newLevel : newLevel - 1)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if result == nil { Button("Cancel", action: onClose) } }
                ToolbarItem(placement: .confirmationAction) {
                    if result == nil { Button("Level Up", action: levelUp).disabled(!isReady) } else { Button("Done", action: onClose) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private func choicesSections(_ rule: AdvancementRule) -> some View {
        let always = rule.required(onLevel: newLevel)
        if !always.isEmpty {
            Section("This level gives") {
                ForEach(always) { choice in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(choice.title).font(.headline)
                        targetPicker(choice, key: choice.id)
                    }
                }
            }
        }
        if rule.choicePoints > 0 {
            Section {
                ForEach(rule.choices) { choice in
                    Stepper(value: Binding(get: { counts[choice.id] ?? 0 }, set: { counts[choice.id] = $0 }), in: 0...((counts[choice.id] ?? 0) + (remaining >= choice.cost ? remaining / choice.cost : 0))) {
                        HStack {
                            Text(choice.title)
                            if choice.cost > 1 { Text("(\(choice.cost) points)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(counts[choice.id] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("Choose how to spend \(rule.choicePoints) points")
            } footer: {
                Text(remaining == 0 ? "All points spent." : "\(remaining) to spend.")
            }
            ForEach(rule.choices.filter { $0.target != nil && (counts[$0.id] ?? 0) > 0 }) { choice in
                ForEach(0..<(counts[choice.id] ?? 0), id: \.self) { index in
                    Section("\(choice.title)\((counts[choice.id] ?? 0) > 1 ? " (\(index + 1))" : "")") { targetPicker(choice, key: "\(choice.id)#\(index)") }
                }
            }
        }
    }

    /// What the player says for a choice, by the kind of target it has.
    @ViewBuilder
    private func targetPicker(_ choice: AdvancementRule.Choice, key: String) -> some View {
        let binding = Binding(get: { selections[key] ?? [] }, set: { selections[key] = $0 })
        switch choice.target {
        case nil:
            EmptyView()
        case .attributes(let keys, let count, _, let marks)?:
            let labels = Dictionary(uniqueKeysWithValues: system.attributes.map { ($0.key, String(localized: $0.label)) })
            let open = Advancement.openAttributes(keys: keys, marks: marks, on: page)
            multiplePicker(binding, options: open.map { ($0, labels[$0] ?? $0) }, count: count, empty: "Every one has been raised this tier.")
        case .entryValues(let entryKey, let count, _)?:
            let names: [String] = { if case .entries(let list)? = page.attributes[entryKey] { list.map(\.name) } else { [] } }()
            multiplePicker(binding, options: names.map { ($0, $0) }, count: count, empty: "There is nothing to raise yet.")
        case .libraryEntry(let list, let entryKey, let filter)?:
            let options = Advancement.options(list: list, filter: filter, key: entryKey, for: page, level: newLevel, system: system)
            Picker("Choose", selection: Binding(get: { binding.wrappedValue.first ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? [] : [$0] })) {
                Text("None").tag("")
                ForEach(options) { entry in Text("\(entry.name) · \(entry.detail ?? "")").tag(entry.key) }
            }
        case .nextSubclassFeatures(let role, let entryKey)?:
            let features = Advancement.nextSubclassFeatures(role: role, key: entryKey, on: page)
            if features.isEmpty { Text("There is nothing further to take.").foregroundStyle(.secondary) }
            ForEach(features, id: \.name) { feature in
                VStack(alignment: .leading) { Text(feature.name).font(.subheadline.weight(.semibold)); Text(feature.text).font(.callout).foregroundStyle(.secondary) }
            }
        case .newEntry?:
            TextField("Name", text: Binding(get: { binding.wrappedValue.first ?? "" }, set: { binding.wrappedValue = [$0] }))
        }
    }

    private func multiplePicker(_ selection: Binding<[String]>, options: [(key: String, label: String)], count: Int, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if options.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(options, id: \.key) { option in
                Toggle(option.label, isOn: Binding(
                    get: { selection.wrappedValue.contains(option.key) },
                    set: { isOn in
                        var chosen = selection.wrappedValue
                        if isOn, chosen.count < count { chosen.append(option.key) } else if !isOn { chosen.removeAll { $0 == option.key } }
                        selection.wrappedValue = chosen
                    }
                ))
            }
            Text("\(selection.wrappedValue.count) of \(count) chosen.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resultSection(_ result: LevelUpResult) -> some View {
        let labels = Dictionary(uniqueKeysWithValues: system.attributes.map { ($0.key, String(localized: $0.label)) })
        return Section("What changed") {
            ForEach(result.changes, id: \.key) { change in Text("\(labels[change.key] ?? change.key): \(Int(change.from)) → \(Int(change.to))") }
            ForEach(result.notes, id: \.self) { Text($0) }
            if result.changes.isEmpty && result.notes.isEmpty { Text("Nothing else changed.") }
        }
    }

    private func levelUp() {
        guard let rule else { return }
        result = Advancement.levelUp(page, rule: rule, formulas: system.formulas, system: system, picks: picks, required: requiredSelections)
    }
}
