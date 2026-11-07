//
//  CharacterBuilderView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A guided flow that makes a level 1 character: name, race, class, background, ability scores, skills,
/// equipment and spells, then a review.
struct CharacterBuilderView: View {
    let world: World
    let onCreate: (Page) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model: CharacterBuilderModel

    init(world: World, onCreate: @escaping (Page) -> Void) {
        self.world = world
        self.onCreate = onCreate
        _model = State(initialValue: CharacterBuilderModel(world: world))
    }

    var body: some View {
        NavigationStack {
            Form { stepContent }
                .formStyle(.grouped)
                .themedScreen()
                .themedRow()
                .themedNavigationTitle(String(localized: title))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                // Moving between steps is at the bottom of the sheet, in plain sight, rather than in the toolbar.
                .safeAreaInset(edge: .bottom) { navigationBar }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var navigationBar: some View {
        HStack {
            Button("Back") { model.goBack() }
                .disabled(!model.canGoBack)
            Spacer()
            Text("Step \((model.steps.firstIndex(of: model.step) ?? 0) + 1) of \(model.steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.canGoForward {
                Button("Next") { model.goForward() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.plan.problems.isEmpty)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private var title: LocalizedStringResource {
        switch model.step {
        case .concept: "New Character"
        case .race: world.edition.raceTermSingular
        case .characterClass: "Class"
        case .background: "Background"
        case .abilities: "Ability Scores"
        case .skills: "Skills"
        case .tools: "Tools"
        case .equipment: "Equipment"
        case .spells: "Spells"
        case .review: "Review"
        }
    }

    private func create() {
        if let page = model.create(in: modelContext) {
            onCreate(page)
            dismiss()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .concept: ConceptStep(model: model)
        case .race: RaceStep(model: model)
        case .characterClass: ClassStep(model: model)
        case .background: BackgroundStep(model: model)
        case .abilities: AbilitiesStep(model: model)
        case .skills: SkillsStep(model: model)
        case .tools: ToolsStep(model: model)
        case .equipment: EquipmentStep(model: model)
        case .spells: SpellsStep(model: model)
        case .review: ReviewStep(model: model)
        }
    }
}

// MARK: Steps

private struct ConceptStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        Section {
            TextField("Name", text: $model.draft.name)
            Picker("Alignment", selection: $model.draft.alignment) {
                Text("None").tag("")
                ForEach(DnD5eSystem.alignments, id: \.self) { Text($0).tag($0) }
            }
        } footer: {
            Text("This builds a level 1 character. You can change anything on its page afterwards.")
        }
    }
}

/// A list of things to pick one from, with the one chosen ticked.
private struct SourcePicker: View {
    let sources: [ContentSource]
    let selection: ContentChoice?
    let onSelect: (ContentSource) -> Void

    var body: some View {
        Section {
            ForEach(sources) { source in
                Button {
                    onSelect(source)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text(source.sourceTitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if source.choice == selection { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(source.choice == selection ? .isSelected : [])
            }
        }
    }
}

/// The traits or features of what's chosen, to read before moving on.
private struct EntriesPreview: View {
    let title: LocalizedStringResource
    let entries: [EntryValue]

    var body: some View {
        if !entries.isEmpty {
            Section(String(localized: title)) {
                ForEach(entries.indices, id: \.self) { index in
                    DisclosureGroup {
                        Text(entries[index].text).font(.callout).textSelection(.enabled)
                    } label: {
                        Text(entries[index].name)
                    }
                }
            }
        }
    }
}

private struct RaceStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        SourcePicker(sources: model.races, selection: model.draft.race) { model.chooseRace($0) }
        if !model.subraces.isEmpty {
            ThemedSection("Subrace") {
                Picker("Subrace", selection: $model.draft.subrace) {
                    Text("None").tag(String?.none)
                    ForEach(model.subraces) { Text($0.name).tag(String?.some($0.key)) }
                }
            }
        }
        if let bonus = model.raceBonus, let choices = bonus.choices {
            Section {
                ForEach(Ability.allCases.filter { bonus.fixed[$0] == nil }) { ability in
                    Toggle(ability.rawValue, isOn: Binding(
                        get: { model.draft.raceBonusChoices.contains(ability) },
                        set: { isOn in
                            model.draft.raceBonusChoices.removeAll { $0 == ability }
                            if isOn { model.draft.raceBonusChoices.append(ability) }
                        }
                    ))
                    .disabled(!model.draft.raceBonusChoices.contains(ability) && model.draft.raceBonusChoices.count >= choices.count)
                }
            } header: {
                Text("Bonus Abilities")
            } footer: {
                Text("Choose \(choices.count) abilities to increase by \(choices.amount).")
            }
        }
        if let race = model.race { EntriesPreview(title: "Traits", entries: race.entries) }
    }
}

private struct ClassStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        SourcePicker(sources: model.classes, selection: model.draft.characterClass) { model.chooseClass($0) }
        if !model.levelOneSubclasses.isEmpty {
            ThemedSection("Subclass") {
                Picker("Subclass", selection: $model.draft.subclass) {
                    Text("None").tag(String?.none)
                    ForEach(model.levelOneSubclasses) { Text($0.name).tag(String?.some($0.key)) }
                }
            }
        }
        if let characterClass = model.characterClass {
            ThemedSection("At a Glance") {
                if let die = characterClass.text("dnd5e.hitDie") { LabeledContent("Hit Die", value: die) }
                if let saves = characterClass.text("dnd5e.savingThrows") { LabeledContent("Saving Throws", value: saves) }
                if let armor = characterClass.text("dnd5e.armorProficiencies") { LabeledContent("Armor", value: armor) }
                if let weapons = characterClass.text("dnd5e.weaponProficiencies") { LabeledContent("Weapons", value: weapons) }
            }
            EntriesPreview(title: "Level 1 Features", entries: characterClass.entries.filter { $0.level == 1 })
        }
    }
}

private struct BackgroundStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        SourcePicker(sources: model.backgrounds, selection: model.draft.background) { model.chooseBackground($0) }
        if let background = model.background {
            ThemedSection("Gives You") {
                ForEach(Self.facts, id: \.key) { fact in
                    if let text = background.text(fact.key) { LabeledContent(fact.label, value: text) }
                }
            }
            if model.edition == .srd52, !model.backgroundAbilities.isEmpty {
                Section {
                    Picker("Increase", selection: bonusKind) {
                        Text("+2 and +1").tag(0)
                        Text("+1 to each").tag(1)
                    }
                    if case .twoAndOne(let two, let one)? = model.draft.backgroundBonus {
                        Picker("+2", selection: Binding(get: { two }, set: { model.draft.backgroundBonus = .twoAndOne(two: $0, one: one) })) {
                            ForEach(model.backgroundAbilities) { Text($0.rawValue).tag($0) }
                        }
                        Picker("+1", selection: Binding(get: { one }, set: { model.draft.backgroundBonus = .twoAndOne(two: two, one: $0) })) {
                            ForEach(model.backgroundAbilities) { Text($0.rawValue).tag($0) }
                        }
                    }
                } header: {
                    Text("Ability Scores")
                } footer: {
                    Text("In these rules the background raises your ability scores, not the species.")
                }
            }
            EntriesPreview(title: "Details", entries: background.entries)
        }
    }

    private static let facts: [(key: String, label: String)] = [
        ("dnd5e.backgroundAbilityScores", "Ability Scores"), ("dnd5e.backgroundFeat", "Feat"), ("dnd5e.backgroundSkills", "Skills"),
        ("dnd5e.backgroundTools", "Tool"), ("dnd5e.backgroundLanguages", "Languages"), ("dnd5e.backgroundEquipment", "Equipment"),
    ]

    private var bonusKind: Binding<Int> {
        Binding(
            get: {
                switch model.draft.backgroundBonus {
                case .twoAndOne?: 0
                case .oneEach?: 1
                case nil: -1
                }
            },
            set: { value in
                if value == 1 {
                    model.draft.backgroundBonus = .oneEach
                } else if let first = model.backgroundAbilities.first, model.backgroundAbilities.count > 1 {
                    model.draft.backgroundBonus = .twoAndOne(two: first, one: model.backgroundAbilities[1])
                }
            }
        )
    }
}

private struct AbilitiesStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        Group { sections }
            // The scores follow the class, race and background until the user sets one themselves.
            .onAppear { model.refreshRecommendation() }
            .onChange(of: model.recommendationKey) { model.refreshRecommendation() }
    }

    @ViewBuilder
    private var sections: some View {
        Section {
            Picker("Method", selection: Binding(get: { model.draft.method }, set: { model.chooseMethod($0) })) {
                Text("Standard Array").tag(ScoreMethod.standardArray)
                Text("Point Buy").tag(ScoreMethod.pointBuy)
                Text("Manual").tag(ScoreMethod.manual)
            }
            .pickerStyle(.segmented)
        } footer: {
            switch model.draft.method {
            case .standardArray: Text("Give each ability one of 15, 14, 13, 12, 10 and 8.")
            case .pointBuy: Text("\(model.pointsSpent) of \(CharacterRules.pointBuyBudget) points spent. Scores go from 8 to 15.")
            case .manual: Text("Enter the scores you rolled or were given.")
            }
        }
        Section {
            ForEach(Ability.allCases) { ability in
                row(for: ability)
            }
        } footer: {
            recommendation
        }
    }

    /// What the suggestion is based on, and a button to apply it again after the user has changed the numbers.
    @ViewBuilder
    private var recommendation: some View {
        if model.draft.method == .standardArray, let priorities = model.recommendedPriorities, let name = model.characterClass?.name {
            VStack(alignment: .leading, spacing: 8) {
                Text("A \(name) usually wants \(priorities.prefix(3).map(\.rawValue).joined(separator: ", ")) highest. Suggested numbers take your species and background bonuses into account.")
                Button("Suggest Scores for \(name)", systemImage: "wand.and.stars") { model.applyRecommendation() }
                    .disabled(!model.scoresEdited)
            }
        }
    }

    private func row(for ability: Ability) -> some View {
        let plan = model.plan
        let bonus = plan.bonuses[ability] ?? 0
        let final = plan.scores[ability] ?? 10
        return LabeledContent {
            HStack {
                control(for: ability)
                Text(bonus == 0 ? "" : "+\(bonus)").foregroundStyle(.secondary).frame(width: 28)
                Text("\(final)").monospacedDigit().frame(width: 28, alignment: .trailing)
                Text(CharacterRules.modifierText(for: final)).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
        } label: {
            Text(ability.rawValue)
        }
    }

    @ViewBuilder
    private func control(for ability: Ability) -> some View {
        switch model.draft.method {
        case .standardArray:
            Picker(ability.rawValue, selection: Binding(get: { model.draft.scores[ability] ?? 10 }, set: { model.assign($0, to: ability) })) {
                ForEach(CharacterRules.standardArray, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
        case .pointBuy:
            Stepper(value: Binding(get: { model.draft.scores[ability] ?? 8 }, set: { model.draft.scores[ability] = $0 }),
                    in: CharacterRules.pointBuyRange) {
                Text("\(model.draft.scores[ability] ?? 8)").monospacedDigit()
            }
        case .manual:
            TextField(ability.rawValue, value: Binding(get: { model.draft.scores[ability] ?? 10 }, set: { model.draft.scores[ability] = $0 }), format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
        }
    }
}

private struct SkillsStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        let plan = model.plan
        if !plan.backgroundSkills.isEmpty {
            ThemedSection("From Your Background") {
                ForEach(plan.backgroundSkills, id: \.self) { Label($0, systemImage: "checkmark.circle.fill") }
            }
        }
        if let choice = plan.classSkillChoice {
            let options = choice.options.filter { !plan.backgroundSkills.contains($0) }
            let picked = model.draft.skills.subtracting(plan.backgroundSkills)
            Section {
                ForEach(options, id: \.self) { skill in
                    Toggle(skill, isOn: Binding(
                        get: { model.draft.skills.contains(skill) },
                        set: { isOn in if isOn { model.draft.skills.insert(skill) } else { model.draft.skills.remove(skill) } }
                    ))
                    .disabled(!model.draft.skills.contains(skill) && picked.count >= choice.count)
                }
            } header: {
                Text("From Your Class")
            } footer: {
                Text("Choose \(choice.count). \(picked.count) chosen.")
            }
        } else {
            Text("Choose a class first.").foregroundStyle(.secondary)
        }
    }
}

private struct ToolsStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        let plan = model.plan
        ForEach(plan.toolChoices) { choice in
            Section {
                ForEach(choice.options, id: \.self) { tool in
                    Toggle(tool, isOn: Binding(
                        get: { choice.picks.contains(tool) },
                        set: { isOn in
                            var picks = model.draft.toolPicks[choice.id] ?? []
                            if isOn { picks.insert(tool) } else { picks.remove(tool) }
                            model.draft.toolPicks[choice.id] = picks
                        }
                    ))
                    .disabled(!choice.picks.contains(tool) && choice.picks.count >= choice.count)
                }
            } header: {
                Text(choice.title)
            } footer: {
                Text("Choose \(choice.count). \(choice.picks.count) chosen.")
            }
        }
        let fixed = plan.tools.filter { tool in !plan.toolChoices.contains { $0.picks.contains(tool) } }
        if !fixed.isEmpty {
            ThemedSection("Also Proficient With") {
                ForEach(fixed, id: \.self) { Label($0, systemImage: "checkmark.circle.fill") }
            }
        }
    }
}

private struct EquipmentStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        let groups = model.plan.equipmentGroups
        if groups.isEmpty {
            Text("Choose a class and background first.").foregroundStyle(.secondary)
        }
        ForEach(groups.indices, id: \.self) { index in
            Section {
                if groups[index].isChoice {
                    Picker("Choose", selection: Binding(get: { model.draft.equipmentChoices[index] ?? -1 }, set: { model.draft.equipmentChoices[index] = $0 })) {
                        Text("Choose…").tag(-1)
                        ForEach(groups[index].options.indices, id: \.self) { option in
                            Text("\(groups[index].options[option].label.isEmpty ? "" : "(\(groups[index].options[option].label)) ")\(groups[index].options[option].text)").tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } else if let only = groups[index].options.first {
                    Text(only.text)
                }
            } header: {
                Text(index == 0 ? "Your Class" : "")
            }
        }
    }
}

private struct SpellsStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        let plan = model.plan
        if let ability = plan.spellLimits.ability {
            Section { LabeledContent("Spellcasting Ability", value: ability.rawValue) }
        }
        SpellList(title: "Cantrips", spells: model.spells(level: 0), selection: $model.draft.cantrips, limit: plan.cantripLimit)
        SpellList(title: "Level 1 Spells", spells: model.spells(level: 1), selection: $model.draft.spells, limit: plan.spellLimit)
    }
}

private struct SpellList: View {
    let title: LocalizedStringResource
    let spells: [LibraryEntry]
    @Binding var selection: Set<String>
    let limit: Int?

    var body: some View {
        if limit != 0 {
            Section {
                ForEach(spells) { spell in
                    Toggle(isOn: Binding(
                        get: { selection.contains(spell.key) },
                        set: { isOn in if isOn { selection.insert(spell.key) } else { selection.remove(spell.key) } }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spell.name)
                            Text(spell.spellHeadline).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!selection.contains(spell.key) && limit.map { selection.count >= $0 } == true)
                }
            } header: {
                Text(String(localized: title))
            } footer: {
                if let limit { Text("\(selection.count) of \(limit) chosen.") }
            }
        }
    }
}

private struct ReviewStep: View {
    @Bindable var model: CharacterBuilderModel

    var body: some View {
        let plan = model.plan
        Section(model.draft.name.isEmpty ? "Unnamed" : model.draft.name) {
            if let race = model.race, let characterClass = model.characterClass {
                Text("\(race.name) \(characterClass.name), level 1")
            }
            if let background = model.background { LabeledContent("Background", value: background.name) }
            if !model.draft.alignment.isEmpty { LabeledContent("Alignment", value: model.draft.alignment) }
        }
        ThemedSection("Ability Scores") {
            ForEach(Ability.allCases) { ability in
                let score = plan.scores[ability] ?? 10
                LabeledContent(ability.rawValue, value: "\(score) (\(CharacterRules.modifierText(for: score)))")
            }
        }
        ThemedSection("Worked Out") {
            if let hitPoints = plan.hitPoints { LabeledContent("Hit Points", value: "\(hitPoints)") }
            if let armorClass = plan.armorClass { LabeledContent("Armor Class", value: "\(armorClass)") }
            LabeledContent("Proficiency Bonus", value: "+\(plan.proficiencyBonus)")
            if !plan.savingThrows.isEmpty { LabeledContent("Saving Throws", value: plan.savingThrows.joined(separator: ", ")) }
            if !plan.skills.isEmpty { LabeledContent("Skills", value: plan.skills.joined(separator: ", ")) }
            if !plan.tools.isEmpty { LabeledContent("Tools", value: plan.tools.joined(separator: ", ")) }
        }
        if !plan.equipment.isEmpty {
            ThemedSection("Equipment") { ForEach(plan.equipment, id: \.self) { Text($0) } }
        }
        if !plan.problems.isEmpty {
            Section {
                ForEach(plan.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            } header: {
                Text("To Do")
            } footer: {
                Text("Go back to a step to finish it, then create the character.")
            }
        }
        if !plan.notes.isEmpty {
            ThemedSection("For You to Fill In") {
                ForEach(plan.notes, id: \.self) { Text($0).font(.callout) }
            }
        }
    }
}

#Preview("Character Builder") {
    let container = SampleData.makePreviewContainer()
    let world = World(name: "Preview", system: .dnd5e)
    container.mainContext.insert(world)
    return CharacterBuilderView(world: world) { _ in }
        .modelContainer(container)
}
