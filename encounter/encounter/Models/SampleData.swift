//
//  SampleData.swift
//  encounter
//

#if DEBUG
import SwiftData

/// Small in-memory data set for previews and tests.
enum SampleData {
    @MainActor
    static func makePreviewContainer(populated: Bool = true) -> ModelContainer {
        do {
            let container = try AppSchema.makeContainer(inMemory: true)
            if populated {
                populate(container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }

    static func populate(_ context: ModelContext) {
        let world = World(name: "Faerûn", summary: "The Forgotten Realms.", system: .dnd5e)
        context.insert(world)

        let region = Page(title: "Sword Coast", kind: .place)
        let settlement = Page(title: "Neverwinter", kind: .place)
        let hero = Page(title: "Aria Vale", kind: .character)
        hero.characterRole = .playable
        let guide = Page(title: "Old Tom", kind: .character)
        let wolf = Page(title: "Dire Wolf", kind: .character)
        let guild = Page(title: "The Harpers", kind: .organisation)
        let elf = Page(title: "Elf", kind: .race)
        let human = Page(title: "Human", kind: .race)

        for page in [region, settlement, hero, guide, wolf, guild, elf, human] {
            context.insert(page)
            page.world = world
        }
        settlement.parent = region
        hero.setLinkedPage(elf, role: "race", in: context)
        guide.setLinkedPage(human, role: "race", in: context)

        context.insert(World(name: "Homebrew Isles"))
    }
}
#endif
