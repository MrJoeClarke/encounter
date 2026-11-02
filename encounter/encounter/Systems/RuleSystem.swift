//
//  RuleSystem.swift
//  encounter
//

import Foundation

/// What a rule system has, as modules. Each is independent and optional: the screens ask the world's system whether it has
/// the module they need and show nothing if it doesn't, so a system with no levels has no Level Up, and a system with no
/// character sheet has no Sheet.
struct RuleModules: OptionSet, Sendable {
    let rawValue: Int

    /// A bundled content library (races, classes and so on) that can be searched, mentioned and built from.
    static let library = RuleModules(rawValue: 1 << 0)
    /// A guided flow that makes a playable character.
    static let characterCreation = RuleModules(rawValue: 1 << 1)
    /// Levelling a playable character up.
    static let advancement = RuleModules(rawValue: 1 << 2)
    /// A sheet to play a character from.
    static let sheet = RuleModules(rawValue: 1 << 3)
    /// Conditions that a character can be under, and what they do to its rolls.
    static let conditions = RuleModules(rawValue: 1 << 4)
}

/// A game system that contributes extra attributes to pages, such as D&D 5e's armor class, and the modules that make up
/// how it is played.
protocol RuleSystem {
    var id: RuleSystemID { get }
    /// What a world stores to say it uses this system. For the systems the app names it is the `RuleSystemID`'s raw value.
    var key: String { get }
    /// Raised when the system's rules change in a way a world made under an older one should know about.
    var version: Int { get }
    /// Attributes this system adds. A definition whose key matches a core attribute replaces it.
    var attributes: [AttributeDefinition] { get }
    /// Page kinds that always appear in the sidebar of a world using this system, such as Classes.
    var additionalPageKinds: Set<PageKind> { get }
    /// The modules the system has.
    var modules: RuleModules { get }
    /// How the system's checks are rolled and read, if it has any.
    var rollModel: RollModel? { get }
    /// How the system works out its numbers, by name.
    var formulas: FormulaSet { get }
    /// The kinds of rest the system has.
    var rests: [RestDefinition] { get }
    /// What a character has that goes down and up in play, and how each kind of rest gives it back.
    var resources: [ResourceDefinition] { get }
    /// Resources the whole world shares, kept on the world, such as the GM's Fear.
    var worldResources: [ResourceDefinition] { get }
    /// How a character is made, if the system has a guided flow for it.
    var creationFlow: CreationFlow? { get }
    /// How a character gains levels, if the system has them.
    var advancement: AdvancementRule? { get }
    /// The conditions a character can be under, and what they do to its rolls.
    var conditions: [ConditionDefinition] { get }
    /// How a character's sheet is laid out, if the system has one.
    var sheetLayout: SheetLayout? { get }
    /// The library editions the system's worlds can use, the first being the one a world starts on. Empty if it has no library.
    var libraryEditions: [LibraryEdition] { get }
    /// Whether the system is shown by the generic creation, level-up and sheet screens, which read it as data, rather than by
    /// screens written for it.
    var usesGenericScreens: Bool { get }
    /// The line shown under an entry's name in a library list, for entries whose pack gives no `detail` of its own.
    func libraryDetail(for entry: LibraryEntry) -> String?
    /// Labels for attributes that only library entries have, which no page editor labels.
    var libraryAttributeLabels: [String: String] { get }
    /// The numbers a score attribute (`AttributeType.abilityScore`) can take.
    var scoreRange: ClosedRange<Int> { get }
}

extension RuleSystem {
    var key: String { id.rawValue }
    var version: Int { 1 }
    var additionalPageKinds: Set<PageKind> { [] }
    var modules: RuleModules { [] }
    var rollModel: RollModel? { nil }
    var formulas: FormulaSet { FormulaSet([:]) }
    var rests: [RestDefinition] { [] }
    var resources: [ResourceDefinition] { [] }
    var worldResources: [ResourceDefinition] { [] }
    var creationFlow: CreationFlow? { nil }
    var advancement: AdvancementRule? { nil }
    var conditions: [ConditionDefinition] { [] }
    var sheetLayout: SheetLayout? { nil }
    var libraryEditions: [LibraryEdition] { [] }
    var usesGenericScreens: Bool { false }
    func libraryDetail(for entry: LibraryEntry) -> String? { entry.detail }
    var libraryAttributeLabels: [String: String] { [:] }
    var scoreRange: ClosedRange<Int> { 1...30 }

    /// Whether the system comes with a bundled content library (races, classes and so on).
    var hasContentLibrary: Bool { modules.contains(.library) }
}

/// No game system: only the core attributes apply.
struct NoRuleSystem: RuleSystem {
    let id = RuleSystemID.none
    let attributes: [AttributeDefinition] = []
}

/// A system a world can choose.
struct SystemChoice: Identifiable, Hashable {
    let key: String
    let title: String
    var id: String { key }
}

/// The systems read from files, by key. The ones that ship with the app are loaded from its bundle the first time they are
/// asked for; others can be added.
final class SystemRegistry: @unchecked Sendable {
    static let shared = SystemRegistry()

    private var systems: [String: DataRuleSystem] = [:]
    private var hasLoadedBundle = false
    private let lock = NSLock()

    /// A registry that holds only what is added to it, for tests.
    init(loadsBundle: Bool = true) {
        hasLoadedBundle = !loadsBundle
    }

    /// Adds a system, replacing one with the same key. A system can't take the key of one the app names.
    @discardableResult
    func register(_ system: DataRuleSystem) -> Bool {
        guard RuleSystemID(rawValue: system.key) == nil else { return false }
        lock.lock()
        defer { lock.unlock() }
        loadBundleIfNeeded()
        systems[system.key] = system
        return true
    }

    func system(forKey key: String) -> DataRuleSystem? {
        lock.lock()
        defer { lock.unlock() }
        loadBundleIfNeeded()
        return systems[key]
    }

    var all: [DataRuleSystem] {
        lock.lock()
        defer { lock.unlock() }
        loadBundleIfNeeded()
        return systems.values.sorted { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending }
    }

    /// Systems that ship with the app are files named `*.system.json` in its bundle.
    private func loadBundleIfNeeded() {
        guard !hasLoadedBundle else { return }
        hasLoadedBundle = true
        let urls = Bundle(for: RegistryBundleToken.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasSuffix(".system.json") {
            if let data = try? Data(contentsOf: url), let system = DataRuleSystem(data: data), RuleSystemID(rawValue: system.key) == nil {
                systems[system.key] = system
            }
        }
    }
}

private final class RegistryBundleToken {}

/// How a world's recorded system compares with what this app has.
enum SystemStatus: Equatable {
    /// The world's system, at the version the world was last used with.
    case current
    /// The system has been updated since the world was last used with it.
    case updated(from: Int, to: Int)
    /// The world was made with a newer version of the system than this app has.
    case newerThanApp(world: Int, app: Int)
    /// The app doesn't have this system. The world keeps its choice and its data, and shows only the core attributes.
    case unknown
}

enum RuleSystems {
    static func system(for id: RuleSystemID) -> any RuleSystem {
        switch id {
        case .none: NoRuleSystem()
        case .dnd5e: DnD5eSystem()
        }
    }

    /// The system a world's stored key names. A key the app doesn't know gives no system, and is never changed.
    static func system(forKey key: String) -> any RuleSystem {
        if let id = RuleSystemID(rawValue: key) { return system(for: id) }
        return SystemRegistry.shared.system(forKey: key) ?? NoRuleSystem()
    }

    /// Whether the app has the system.
    static func isKnown(_ key: String) -> Bool {
        RuleSystemID(rawValue: key) != nil || SystemRegistry.shared.system(forKey: key) != nil
    }

    /// The systems a world can choose: those the app names, then those read from files.
    static var choices: [SystemChoice] {
        RuleSystemID.allCases.map { SystemChoice(key: $0.rawValue, title: String(localized: $0.title)) }
            + SystemRegistry.shared.all.map { SystemChoice(key: $0.key, title: $0.definition.name) }
    }

    /// What to call a stored system key: its name, or the key itself if the app doesn't know it.
    static func title(forKey key: String) -> String {
        choices.first { $0.key == key }?.title ?? key
    }

    /// Compares the version a world recorded with the one the app has. A world that recorded none counts as current.
    static func status(key: String, recordedVersion: Int?) -> SystemStatus {
        guard isKnown(key) else { return .unknown }
        let app = system(forKey: key).version
        guard let recorded = recordedVersion, recorded > 0 else { return .current }
        if recorded > app { return .newerThanApp(world: recorded, app: app) }
        return recorded < app ? .updated(from: recorded, to: app) : .current
    }

    /// The attributes for a page kind under a rule system, by the key a world stores.
    static func definitions(for kind: PageKind, systemKey key: String) -> [AttributeDefinition] {
        definitions(for: kind, rules: system(forKey: key))
    }

    /// The attributes for a page kind under a rule system: the core attributes, with any the system
    /// overrides replaced in place, followed by the system's additions.
    /// Values for attributes not listed here stay stored on the page, so switching systems loses nothing.
    static func definitions(for kind: PageKind, system id: RuleSystemID) -> [AttributeDefinition] {
        definitions(for: kind, rules: system(for: id))
    }

    private static func definitions(for kind: PageKind, rules: any RuleSystem) -> [AttributeDefinition] {
        var result = CoreAttributes.definitions(for: kind)
        for definition in rules.attributes where definition.appliesTo.contains(kind) {
            if let index = result.firstIndex(where: { $0.key == definition.key }) {
                result[index] = definition
            } else {
                result.append(definition)
            }
        }
        return result
    }
}
