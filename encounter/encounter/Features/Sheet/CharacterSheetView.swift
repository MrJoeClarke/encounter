//
//  CharacterSheetView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// What a tap on the sheet opens an action card for.
enum SheetAction: Identifiable, Hashable {
    case ability(Ability)
    case save(Ability)
    case skill(String)
    case initiative
    case deathSave
    case attack(String)
    case spell(String)

    var id: Self { self }
}

/// A character's sheet for playing: the numbers worked out from the character, with weapons, spells, checks and
/// saves that open a card saying what to roll. What is played (hit points, slots) is written back to the character.
struct CharacterSheetView: View {
    let page: Page

    @AppStorage("rollsInApp") private var rollsInApp = false
    @State private var log = RollLog()
    @State private var action: SheetAction?
    @State private var amount = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let sheet = CharacterSheet(page: page) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(sheet)
                    stats(sheet)
                    // Two columns where there is room, one on a phone.
                    let layout = sizeClass == .compact ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    layout {
                        VStack(spacing: 16) {
                            hitPoints(sheet)
                            ConditionsBox(page: page)
                            abilities(sheet)
                            checks(sheet)
                        }
                        VStack(spacing: 16) {
                            attacks(sheet)
                            spellcasting(sheet)
                            features(sheet)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    if rollsInApp, !log.entries.isEmpty { rollLog }
                }
                .padding()
            }
            .sheet(item: $action) { selected in
                ActionCardView(page: page, action: selected, rollsInApp: rollsInApp, log: log) { action = nil }
            }
        } else {
            ContentUnavailableView("No Sheet", systemImage: "person.text.rectangle",
                                   description: Text("A sheet is made for characters in a D&D world."))
        }
    }

    // MARK: Boxes

    private func box<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func bonus(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    private func header(_ sheet: CharacterSheet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.name).font(.largeTitle.weight(.semibold))
                Text(sheet.subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $rollsInApp) {
                Label("Roll Dice Here", systemImage: "dice")
            }
            .toggleStyle(.button)
            .help("Show Roll buttons on the action cards. Off, the cards only say what to roll.")
        }
    }

    private func stats(_ sheet: CharacterSheet) -> some View {
        HStack(spacing: 12) {
            statTile("Armor Class", sheet.armorClass.map(String.init) ?? "—")
            Button { action = .initiative } label: { statTile("Initiative", bonus(sheet.initiative)) }
                .buttonStyle(.plain)
            statTile("Speed", sheet.speed.isEmpty ? "—" : sheet.effectiveSpeed, tint: sheet.speedIsChanged ? .orange : nil)
            statTile("Proficiency", bonus(sheet.proficiencyBonus))
            statTile("Passive Perception", String(sheet.passivePerception))
        }
    }

    private func statTile(_ title: LocalizedStringKey, _ value: String, tint: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(tint ?? .primary)
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    // MARK: Hit points

    private func hitPoints(_ sheet: CharacterSheet) -> some View {
        box("Hit Points") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sheet.currentHitPoints)").font(.system(size: 40, weight: .semibold))
                Text("/ \(sheet.maximumHitPoints)").font(.title3).foregroundStyle(.secondary)
                if sheet.temporaryHitPoints > 0 {
                    Text("+\(sheet.temporaryHitPoints) temporary").font(.callout).foregroundStyle(.blue)
                }
            }
            HStack {
                TextField("Amount", value: $amount, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Damage") { sheet.takeDamage(amount); amount = 0 }
                Button("Heal") { sheet.heal(amount); amount = 0 }
                Button("Temp") { sheet.gainTemporaryHitPoints(amount); amount = 0 }
            }
            .buttonStyle(.bordered)
            .disabled(false)
            if sheet.isAtZero { deathSaves(sheet) }
            if let sides = sheet.hitDieSides {
                HStack {
                    Text("Hit Dice: \(sheet.hitDiceRemaining) of \(sheet.level) (d\(sides))")
                    Spacer()
                    Button("Use One") {
                        sheet.spendHitDie(rolled: rollsInApp ? DiceRoller.roll(DiceExpression(count: 1, sides: sides)).total : nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(sheet.hitDiceRemaining == 0 || sheet.currentHitPoints >= sheet.maximumHitPoints)
                }
                .font(.callout)
            }
            HStack {
                Button("Short Rest", systemImage: "cup.and.saucer") { sheet.shortRest() }
                Button("Long Rest", systemImage: "bed.double") { sheet.longRest() }
            }
            .buttonStyle(.bordered)
        }
    }

    /// The marks of a death saving throw, tapped by hand or filled in from a roll on its card.
    private func deathSaves(_ sheet: CharacterSheet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if sheet.isDead {
                Label("Dead", systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.headline)
            } else if sheet.isStable {
                Label("Stable", systemImage: "heart.circle").foregroundStyle(.green).font(.headline)
            } else {
                Label("Dying: make a death saving throw each turn", systemImage: "waveform.path.ecg").foregroundStyle(.orange).font(.callout)
            }
            HStack {
                Text("Successes")
                marks(count: sheet.deathSaveSuccesses, tint: .green) { sheet.setDeathSaves(successes: $0, failures: sheet.deathSaveFailures) }
                Spacer()
                Text("Failures")
                marks(count: sheet.deathSaveFailures, tint: .red) { sheet.setDeathSaves(successes: sheet.deathSaveSuccesses, failures: $0) }
            }
            .font(.callout)
            HStack {
                Button("Death Saving Throw…", systemImage: "dice") { action = .deathSave }
                Button("Reset") { sheet.resetDeathSaves() }
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func marks(count: Int, tint: Color, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Button { set(index < count ? index : index + 1) } label: {
                    Image(systemName: index < count ? "circle.fill" : "circle").foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Abilities, saves and skills

    private func abilities(_ sheet: CharacterSheet) -> some View {
        box("Abilities") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Ability.allCases) { ability in
                    Button { action = .ability(ability) } label: {
                        VStack(spacing: 2) {
                            Text(ability.rawValue.prefix(3).uppercased()).font(.caption).foregroundStyle(.secondary)
                            Text(bonus(sheet.modifier(ability))).font(.title2.weight(.semibold))
                            Text("\(sheet.scores[ability] ?? 10)").font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func checks(_ sheet: CharacterSheet) -> some View {
        box("Saving Throws and Skills") {
            ForEach(sheet.saves) { save in
                checkRow(title: save.ability.rawValue, bonus: save.bonus, symbol: save.isProficient ? "circle.inset.filled" : "circle",
                         help: "Proficient saving throw. Click to change.",
                         cycle: { sheet.setSave(save.ability, proficient: !save.isProficient) }) { action = .save(save.ability) }
            }
            Divider()
            ForEach(sheet.skills) { skill in
                checkRow(title: skill.name, detail: String(skill.ability.rawValue.prefix(3)), bonus: skill.bonus, symbol: symbol(for: skill.proficiency),
                         help: "Click to cycle: not proficient, proficient, expertise (double the proficiency bonus).",
                         cycle: { sheet.setSkill(skill.name, to: skill.proficiency == .proficient ? .expertise : skill.proficiency == .expertise ? .none : .proficient) }
                ) { action = .skill(skill.name) }
            }
        }
    }

    private func symbol(for proficiency: SkillProficiency) -> String {
        switch proficiency {
        case .none: "circle"
        case .half: "circle.lefthalf.filled"
        case .proficient: "circle.inset.filled"
        case .expertise: "star.circle.fill"
        }
    }

    private func checkRow(
        title: String, detail: String = "", bonus number: Int, symbol: String, help: LocalizedStringKey,
        cycle: @escaping () -> Void, open: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: cycle) { Image(systemName: symbol) }
                .buttonStyle(.plain)
                .help(help)
            Button(action: open) {
                HStack {
                    Text(title)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text(bonus(number)).monospacedDigit().fontWeight(.medium)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Attacks

    @ViewBuilder
    private func attacks(_ sheet: CharacterSheet) -> some View {
        let attacks = sheet.attacks
        box("Attacks") {
            if attacks.isEmpty {
                Text("No weapons in the equipment. Weapons from the library are picked up by name.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(attacks) { attack in
                Button { action = .attack(attack.weapon.name) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attack.weapon.name)
                            Text(attack.weapon.properties.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(bonus(attack.attackBonus) + " to hit").fontWeight(.medium)
                            Text("\(attack.damage.text) \(attack.weapon.damageType)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Spells

    @ViewBuilder
    private func spellcasting(_ sheet: CharacterSheet) -> some View {
        let spells = sheet.spells
        if sheet.progression?.castsSpells == true || !spells.isEmpty {
            box("Spellcasting") {
                if let ability = sheet.spellcastingAbility, let dc = sheet.spellSaveDC, let attack = sheet.spellAttackBonus {
                    HStack {
                        Text(ability.rawValue)
                        Spacer()
                        Text("Save DC \(dc)")
                        Text("Attack \(bonus(attack))")
                    }
                    .font(.callout)
                }
                slotRows(sheet)
                ForEach(spellLevels(spells), id: \.self) { level in
                    Text(level == 0 ? String(localized: "Cantrips") : String(localized: "\(ClassProgression.ordinal(level)) Level"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    ForEach(spells.filter { $0.level == level }) { spell in
                        Button { action = .spell(spell.name) } label: {
                            HStack {
                                Text(spell.name)
                                if spell.isRitual { Text("ritual").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func spellLevels(_ spells: [SheetSpell]) -> [Int] {
        Array(Set(spells.map(\.level))).sorted()
    }

    @ViewBuilder
    private func slotRows(_ sheet: CharacterSheet) -> some View {
        let maximum = sheet.slotsByLevel
        let used = sheet.slotsUsed
        ForEach(0..<9, id: \.self) { index in
            if maximum[index] > 0 {
                HStack(spacing: 6) {
                    Text(sheet.usesPactMagic ? String(localized: "Pact slots, \(ClassProgression.ordinal(index + 1)) level") : "\(ClassProgression.ordinal(index + 1))")
                        .font(.callout)
                        .frame(width: sheet.usesPactMagic ? nil : 36, alignment: .leading)
                    ForEach(0..<maximum[index], id: \.self) { dot in
                        let isAvailable = dot >= used[index]
                        Button {
                            sheet.setSlotsUsed(level: index + 1, to: used[index] + (isAvailable ? 1 : -1))
                        } label: {
                            Image(systemName: isAvailable ? "circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAvailable ? "Slot available" : "Slot used")
                    }
                    Spacer()
                    Text("\(maximum[index] - used[index]) left").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Features

    @ViewBuilder
    private func features(_ sheet: CharacterSheet) -> some View {
        ForEach(featureLists, id: \.key) { list in
            if case .entries(let entries)? = page.attributes[list.key], !entries.isEmpty {
                box(list.title) {
                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]
                        if entry.text.isEmpty {
                            Text(entry.name)
                        } else {
                            DisclosureGroup {
                                Text(entry.text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                HStack {
                                    Text(entry.name)
                                    if let level = entry.level { Spacer(); Text("Level \(level)").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var featureLists: [(key: String, title: LocalizedStringKey)] {
        [("dnd5e.classFeatures", "Class Features"), ("dnd5e.feats", "Feats"), ("dnd5e.racialTraits", "Traits"), ("dnd5e.equipment", "Equipment")]
    }

    // MARK: Rolls

    private var rollLog: some View {
        box("Recent Rolls") {
            ForEach(log.entries) { entry in
                HStack {
                    Text(entry.title)
                    Spacer()
                    Text(entry.breakdown).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Clear", role: .destructive) { log.entries.removeAll() }.buttonStyle(.borderless)
        }
    }
}

/// The rolls made on the sheet, newest first.
@Observable
final class RollLog {
    struct Entry: Identifiable {
        let id = UUID()
        var title: String
        var breakdown: String
    }

    var entries: [Entry] = []

    func add(title: String, result: RollResult) {
        entries.insert(Entry(title: title, breakdown: result.breakdown), at: 0)
        if entries.count > 12 { entries.removeLast(entries.count - 12) }
    }
}

#Preview("Wizard, level 5") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview", system: .dnd5e)
    world.edition = .srd51
    context.insert(world)
    let page = world.addPage(kind: .character, in: context)
    page.title = "Mira Vale"
    page.characterRole = .playable
    page.setReference(.library("srd51.race.human"), role: LinkRole.race, in: context)
    page.setReference(.library("srd51.class.wizard"), role: LinkRole.characterClass, in: context)
    page.setReference(.library("srd51.background.acolyte"), role: LinkRole.background, in: context)
    page.setAttributeNumber("dnd5e.classLevel", 5)
    page.setAttributeNumber("dnd5e.hitPoints", 28)
    page.setAttributeNumber("dnd5e.currentHitPoints", 19)
    page.setAttributeNumber("dnd5e.armorClass", 12)
    page.setAttributeNumber("dnd5e.proficiencyBonus", 3)
    page.setAttributeText("dnd5e.speed", "30 feet")
    let scores: [Ability: Double] = [.strength: 8, .dexterity: 14, .constitution: 13, .intelligence: 17, .wisdom: 12, .charisma: 10]
    for (ability, score) in scores { page.setAttributeNumber(ability.attributeKey, score) }
    page.setAttributeText("dnd5e.savingThrowProficiencies", "Intelligence, Wisdom")
    page.setAttributeText("dnd5e.skillProficiencies", "Arcana, History, Insight")
    page.setAttributeText("dnd5e.spellSlotsUsed", "1,0,0")
    page.attributes["dnd5e.equipment"] = .entries([EntryValue(name: "a dagger"), EntryValue(name: "a quarterstaff"), EntryValue(name: "a spellbook")])
    page.attributes["dnd5e.spells"] = .entries(["Fire Bolt", "Light", "Magic Missile", "Shield", "Fireball", "Misty Step"].map { EntryValue(name: $0) })
    return CharacterSheetView(page: page)
        .modelContainer(container)
        .frame(width: 1000, height: 900)
}

#Preview("Bard, down") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview", system: .dnd5e)
    world.edition = .srd51
    context.insert(world)
    let page = world.addPage(kind: .character, in: context)
    page.title = "Tam Reed"
    page.characterRole = .playable
    page.setReference(.library("srd51.class.bard"), role: LinkRole.characterClass, in: context)
    page.setAttributeNumber("dnd5e.classLevel", 3)
    page.setAttributeNumber("dnd5e.hitPoints", 20)
    page.setAttributeNumber("dnd5e.currentHitPoints", 0)
    page.setAttributeNumber("dnd5e.deathSaveSuccesses", 1)
    page.setAttributeNumber("dnd5e.deathSaveFailures", 2)
    page.setAttributeNumber("dnd5e.proficiencyBonus", 2)
    page.setAttributeNumber("dnd5e.charisma", 16)
    page.setAttributeText("dnd5e.skillProficiencies", "Performance, Persuasion, Deception")
    page.setAttributeText("dnd5e.skillExpertise", "Performance")
    page.attributes["dnd5e.classFeatures"] = .entries([EntryValue(name: "Jack of All Trades", level: 2, text: "Half your proficiency bonus.")])
    return CharacterSheetView(page: page)
        .modelContainer(container)
        .frame(width: 1000, height: 900)
}

#Preview("Fighter, under conditions") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview", system: .dnd5e)
    world.edition = .srd52
    context.insert(world)
    let page = world.addPage(kind: .character, in: context)
    page.title = "Brannoch"
    page.characterRole = .playable
    page.setReference(.library("srd52.class.fighter"), role: LinkRole.characterClass, in: context)
    page.setAttributeNumber("dnd5e.classLevel", 5)
    page.setAttributeNumber("dnd5e.hitPoints", 44)
    page.setAttributeNumber("dnd5e.armorClass", 18)
    page.setAttributeNumber("dnd5e.proficiencyBonus", 3)
    page.setAttributeText("dnd5e.speed", "30 feet")
    page.setAttributeNumber("dnd5e.strength", 17)
    page.setAttributeText("dnd5e.conditions", "Poisoned, Prone, Restrained")
    page.setAttributeNumber("dnd5e.exhaustionLevel", 2)
    page.attributes["dnd5e.equipment"] = .entries([EntryValue(name: "a longsword")])
    return CharacterSheetView(page: page)
        .modelContainer(container)
        .frame(width: 1000, height: 900)
}
