//
//  SampleData.swift
//  encounter
//

#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

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

        hero.body = AttributedString("Born near ") + Mention.mention(title: settlement.title, pageID: settlement.id)
            + AttributedString(", with the blood of the ") + Mention.mention(title: elf.title, pageID: elf.id)
            + AttributedString(". Friends with ") + Mention.mention(title: guide.title, pageID: guide.id)
            + AttributedString(".")
        hero.updateSearchText()
        for page in [hero, guide, region, settlement, elf] {
            MentionSync.sync(page, in: context)
        }

        hero.setAttributeText("core.creatureType", "Humanoid")
        hero.setAttributeText("dnd5e.size", "Medium")
        hero.setAttributeText("dnd5e.alignment", "Neutral Good")
        hero.setAttributeNumber("dnd5e.armorClass", 15)
        hero.setAttributeNumber("dnd5e.hitPoints", 38)
        for (key, score) in [("strength", 10), ("dexterity", 17), ("constitution", 13), ("intelligence", 9), ("wisdom", 14), ("charisma", 12)] {
            hero.setAttributeNumber("dnd5e.\(key)", Double(score))
        }
        wolf.setAttributeText("core.creatureType", "Beast")
        wolf.setAttributeText("dnd5e.challengeRating", "1")

        let portraits: [(red: Double, green: Double, blue: Double)] = [(0.25, 0.45, 0.8), (0.8, 0.45, 0.25), (0.3, 0.7, 0.4)]
        for color in portraits {
            let data = solidImage(width: 600, height: 400, red: color.red, green: color.green, blue: color.blue)
            if let prepared = ImageProcessing.prepareSynchronously(data) {
                hero.addImage(prepared, in: context)
            }
        }

        for color in [(0.2, 0.4, 0.6), (0.6, 0.35, 0.2)] {
            let data = solidImage(width: 900, height: 500, red: color.0, green: color.1, blue: color.2)
            if let prepared = ImageProcessing.prepareSynchronously(data) {
                world.addImage(prepared, in: context)
            }
        }

        // Every world has a root place at the top of its hierarchy.
        world.ensureRootPlace(in: context)

        let homebrew = World(name: "Homebrew Isles")
        context.insert(homebrew)
        homebrew.ensureRootPlace(in: context)
    }

    /// A plain-colour image, JPEG normally or PNG with an alpha channel. For previews and tests.
    static func solidImage(
        width: Int,
        height: Int,
        red: Double = 0.5,
        green: Double = 0.5,
        blue: Double = 0.5,
        withAlpha: Bool = false
    ) -> Data {
        let alphaInfo: CGImageAlphaInfo = withAlpha ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else {
            fatalError("Could not create bitmap context")
        }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let output = NSMutableData()
        let type = withAlpha ? UTType.png : UTType.jpeg
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else {
            fatalError("Could not encode sample image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}
#endif
