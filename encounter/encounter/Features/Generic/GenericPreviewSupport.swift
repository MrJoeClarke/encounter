//
//  GenericPreviewSupport.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A Daggerheart world with one character made through the builder, for the previews of the generic screens.
@MainActor
enum GenericPreviewData {
    static func make() -> (container: ModelContainer, world: World, character: Page)? {
        guard let container = try? AppSchema.makeContainer(inMemory: true) else { return nil }
        let context = container.mainContext
        let world = World(name: "Demo")
        context.insert(world)
        world.choose(systemKey: "daggerheart")
        guard let model = GenericBuilderModel(world: world) else { return nil }
        func pick(_ id: String, _ name: String? = nil) {
            guard let step = model.flow.steps.first(where: { $0.id == id }) else { return }
            let options = model.options(for: step)
            if let option = name.flatMap({ name in options.first { $0.name == name } }) ?? options.first { model.choose(option, for: step) }
        }
        model.draft.name = "Ash"
        pick("class", "Bard")
        pick("ancestry", "Human")
        pick("community", "Wanderborne")
        pick("subclass")
        model.draft.names["experiences"] = ["Blacksmith", "Wanderer"]
        if let step = model.flow.steps.first(where: { $0.id == "domainCards" }) {
            for option in model.options(for: step).prefix(2) { model.togglePick(option, for: step) }
        }
        guard let character = model.create(in: context) else { return nil }
        character.setAttributeNumber("daggerheart.hitPointsMarked", 2)
        character.setAttributeNumber("daggerheart.stressMarked", 3)
        return (container, world, character)
    }
}
