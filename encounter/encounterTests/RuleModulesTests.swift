//
//  RuleModulesTests.swift
//  encounterTests
//

import Testing
import Foundation
@testable import encounter

struct RuleModulesTests {
    @Test func dndHasEveryModuleAndNoSystemHasNone() {
        let dnd = RuleSystems.system(for: .dnd5e).modules
        #expect(dnd.isSuperset(of: [.library, .characterCreation, .advancement, .sheet, .conditions]))
        #expect(RuleSystems.system(for: .none).modules.isEmpty)
        // The old question is the new one.
        #expect(RuleSystems.system(for: .dnd5e).hasContentLibrary && !RuleSystems.system(for: .none).hasContentLibrary)
    }

    @MainActor
    @Test func aWorldAsksItsSystemWhatItHas() {
        let dnd = World(name: "A", system: .dnd5e)
        let plain = World(name: "B", system: .none)
        #expect(dnd.rules.contains(.sheet) && dnd.rules.contains(.advancement))
        #expect(plain.rules.isEmpty)
        plain.system = .dnd5e
        #expect(plain.rules.contains(.library))
    }
}

/// The screens and flows ask what a rule system has. They don't name a system, since a second system would then have to
/// change them. Anything that still does is listed here with how many times, and the list may only get shorter.
struct ScreensDoNotNameASystemTests {
    /// Files that name D&D, outside previews, and how many times each does. Each later step of the modular rules work
    /// moves these behind a module and removes the entry.
    private static let knownDnDScreens: [String: Int] = [
        "Features/Sheet/CharacterSheetView.swift": 1,
        "Features/Builder/CharacterBuilderModel.swift": 1,
        "Features/Builder/CharacterBuilderView.swift": 7,
        "Features/Builder/LevelUpView.swift": 1,
    ]

    private func featuresFolder() -> URL {
        // .../encounterTests/RuleModulesTests.swift -> .../encounter/Features
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("encounter/Features")
    }

    @Test func noScreenNamesASystemThatIsntListed() throws {
        let root = featuresFolder()
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("Can't read the screens at \(root.path)")
            return
        }
        var counts: [String: Int] = [:]
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Previews build sample characters, so only the code before the first one counts.
            let code = text.components(separatedBy: "#Preview").first ?? text
            let hits = code.components(separatedBy: .newlines).filter { $0.contains("dnd5e") || $0.contains("DnD5e") || $0.contains(".dnd5e") }.count
            if hits > 0 { counts[String(url.path.dropFirst(root.deletingLastPathComponent().path.count + 1))] = hits }
        }
        for (file, hits) in counts {
            #expect(hits <= (Self.knownDnDScreens[file] ?? 0), "\(file) names D&D \(hits) times; ask the rule system instead")
        }
        // An entry that is no longer needed is removed, so the list only gets shorter.
        for (file, allowed) in Self.knownDnDScreens {
            #expect((counts[file] ?? 0) == allowed, "\(file) now names D&D \((counts[file] ?? 0)) times, not \(allowed): update the list")
        }
    }
}

/// The screens everyone shares (library lists and entries, page fields) ask the world's system for what is particular to it.
@MainActor
struct GenericScreenSeamTests {
    @Test func aLibraryRowsLineComesFromTheSystemOfTheWorld() throws {
        let barbarian = try #require(Library.shared.entry(forKey: "srd52.class.barbarian"))
        let line = try #require(DnD5eSystem().libraryDetail(for: barbarian))
        #expect(line.hasPrefix("Hit die d12") && line.contains("Strength"))
        let assassin = try #require(Library.shared.entry(forKey: "daggerheart.class.assassin"))
        let daggerheart = RuleSystems.system(forKey: "daggerheart")
        #expect(daggerheart.libraryDetail(for: assassin) == "HP 5 · Evasion 12 · Blade, Midnight")
        // A system that says nothing shows what the pack says, and D&D prefers the pack's line when it has one.
        #expect(NoRuleSystem().libraryDetail(for: assassin) == assassin.detail && NoRuleSystem().libraryDetail(for: barbarian) == nil)
        #expect(DnD5eSystem().libraryDetail(for: assassin) == assassin.detail)
    }

    @Test func aScoreShowsItsModifierByTheSystemsOwnFormula() {
        #expect(RuleSystems.system(forKey: "dnd5e").formulas.integer("abilityModifier", ["score": 15]) == 2)
        #expect(RuleSystems.system(forKey: "dnd5e").formulas.integer("abilityModifier", ["score": 8]) == -1)
        #expect(RuleSystems.system(forKey: "daggerheart").formulas.integer("abilityModifier", ["score": 15]) == nil)
        #expect(DnD5eSystem().scoreRange == 1...30 && NoRuleSystem().scoreRange == 1...30)
    }

    @Test func anEntryIsShownWithTheAttributesOfTheWorldsSystem() {
        let daggerheart = RuleSystems.definitions(for: .characterClass, systemKey: "daggerheart").map(\.key)
        #expect(daggerheart.contains("daggerheart.hitPoints") && !daggerheart.contains("dnd5e.hitDie"))
        let dnd = RuleSystems.definitions(for: .characterClass, systemKey: "dnd5e").map(\.key)
        #expect(dnd.contains("dnd5e.hitDie") && !dnd.contains("daggerheart.hitPoints"))
        #expect(DnD5eSystem().libraryAttributeLabels["dnd5e.ability"] == "Ability" && RuleSystems.system(forKey: "daggerheart").libraryAttributeLabels.isEmpty)
    }
}
