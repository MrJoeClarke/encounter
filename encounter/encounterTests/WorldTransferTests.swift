//
//  WorldTransferTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
import UniformTypeIdentifiers
@testable import encounter

@MainActor
struct WorldTransferTests {
    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    private func prepared(_ red: Double) throws -> PreparedImage {
        try #require(ImageProcessing.prepareSynchronously(SampleData.solidImage(width: 60, height: 40, red: red)))
    }

    /// A world that touches every model and field the format carries.
    private func makeRichWorld(in context: ModelContext) throws -> World {
        let world = World(name: "Faerûn", summary: "The Forgotten Realms.", system: .dnd5e)
        context.insert(world)
        world.calendar?.hoursPerDay = 20
        world.calendar?.months = [
            CalendarMonth(name: "Frost", dayCount: 25),
            CalendarMonth(name: "Bloom", dayCount: 31),
            CalendarMonth(name: "Harvest", dayCount: 28),
        ]
        world.calendar?.weekdays = ["Moonday", "Sunday"]

        let campaign = Campaign(name: "Lost Mine", summary: "Level 1 to 5")
        context.insert(campaign)
        campaign.world = world

        let region = world.addPage(kind: .place, in: context)
        region.title = "Sword Coast"
        let town = world.addPage(kind: .place, in: context)
        town.title = "Neverwinter"
        town.parent = region

        let elf = world.addPage(kind: .race, in: context)
        elf.title = "Elf"

        let hero = world.addPage(kind: .character, in: context)
        hero.title = "Aria Vale"
        hero.summary = "A ranger."
        hero.characterRole = .playable
        hero.tags = ["hero", "ranger"]
        hero.attributes = [
            "dnd5e.armorClass": .number(15),
            "core.creatureType": .text("Humanoid"),
            "dnd5e.requiresAttunement": .bool(true),
            "dnd5e.languages": .list(["Common", "Elvish"]),
        ]
        var body = AttributedString("Born in the north.")
        if let range = body.range(of: "north") {
            body[range].inlinePresentationIntent = .stronglyEmphasized
        }
        hero.body = body
        hero.setLinkedPage(elf, role: "race", in: context)
        hero.setLinkedPage(town, role: "home", in: context)

        let first = hero.addImage(try prepared(0.1), caption: "Front", in: context)
        hero.addImage(try prepared(0.5), caption: "Side", in: context)
        hero.addImage(try prepared(0.9), caption: "Back", in: context)
        hero.setDefaultImage(try #require(hero.sortedImages.dropFirst().first))
        _ = first

        world.addImage(try prepared(0.2), caption: "Coast at dawn", in: context)
        let cover = world.addImage(try prepared(0.7), caption: "Coast at dusk", in: context)
        world.setDefaultImage(cover)

        let event = world.addPage(kind: .event, in: context)
        event.title = "The Ambush"
        event.eventOrigin = .campaign
        event.campaign = campaign
        event.startDate = InWorldDate(year: 1492, month: 2, day: 14, hour: 6)
        event.endDate = InWorldDate(year: 1492, month: 2, day: 14, hour: 9)
        event.setLinkedPage(hero, role: "participant", in: context)

        let map = WorldMap(name: "Sword Coast Map", imageData: SampleData.solidImage(width: 80, height: 50, blue: 0.8))
        context.insert(map)
        map.world = world
        map.place = region
        let pin = MapPin(x: 0.25, y: 0.75)
        context.insert(pin)
        pin.map = map
        pin.target = town

        try context.save()
        return world
    }

    /// Exports a world and reads it back through the real package format.
    private func roundTrip(_ world: World) throws -> WorldPackageContents {
        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        return try WorldPackage.contents(of: wrapper)
    }

    // MARK: Round trip

    @Test func aRichWorldSurvivesExportAndImport() async throws {
        let source = try makeContext()
        let original = try makeRichWorld(in: source)
        let contents = try roundTrip(original)

        let target = try makeContext()
        let (imported, summary) = await WorldImporter.importWorld(contents, into: target)

        // World and calendar
        #expect(imported.name == "Faerûn")
        #expect(imported.summary == "The Forgotten Realms.")
        #expect(imported.system == .dnd5e)
        let calendar = try #require(imported.calendar)
        #expect(calendar.hoursPerDay == 20)
        #expect(calendar.months.map(\.name) == ["Frost", "Bloom", "Harvest"])
        #expect(calendar.months.map(\.dayCount) == [25, 31, 28])
        #expect(calendar.weekdays == ["Moonday", "Sunday"])
        #expect(calendar.daysPerYear == 84)

        // Pages
        let pages = Dictionary(uniqueKeysWithValues: (imported.pages ?? []).map { ($0.title, $0) })
        #expect(pages.count == 5)
        let hero = try #require(pages["Aria Vale"])
        #expect(hero.kind == .character)
        #expect(hero.characterRole == .playable)
        #expect(hero.summary == "A ranger.")
        #expect(hero.tags == ["hero", "ranger"])
        #expect(hero.attributes == [
            "dnd5e.armorClass": .number(15),
            "core.creatureType": .text("Humanoid"),
            "dnd5e.requiresAttunement": .bool(true),
            "dnd5e.languages": .list(["Common", "Elvish"]),
        ])

        // Formatted notes keep their formatting
        #expect(String(hero.body.characters) == "Born in the north.")
        #expect(hero.body.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })

        // Hierarchy and links
        #expect(pages["Neverwinter"]?.parent === pages["Sword Coast"])
        #expect(hero.linkedPage(role: "race") === pages["Elf"])
        #expect(hero.linkedPage(role: "home") === pages["Neverwinter"])

        // Images keep their order, captions, default flag and bytes
        let originalHero = try #require((original.pages ?? []).first { $0.title == "Aria Vale" })
        #expect(hero.sortedImages.map(\.caption) == ["Front", "Side", "Back"])
        #expect(hero.sortedImages.map(\.isDefault) == [false, true, false])
        #expect(hero.sortedImages.map(\.imageData) == originalHero.sortedImages.map(\.imageData))
        #expect(hero.sortedImages.allSatisfy { $0.thumbnailData != nil })

        // Events
        let event = try #require(pages["The Ambush"])
        #expect(event.eventOrigin == .campaign)
        #expect(event.campaign?.name == "Lost Mine")
        #expect(event.campaign?.summary == "Level 1 to 5")
        #expect(event.startDate == InWorldDate(year: 1492, month: 2, day: 14, hour: 6))
        #expect(event.endDate == InWorldDate(year: 1492, month: 2, day: 14, hour: 9))
        #expect(event.linkedPage(role: "participant") === hero)

        // Maps
        let map = try #require(imported.maps?.first)
        #expect(map.name == "Sword Coast Map")
        #expect(map.imageData == original.maps?.first?.imageData)
        #expect(map.place === pages["Sword Coast"])
        let pin = try #require(map.pins?.first)
        #expect(pin.x == 0.25)
        #expect(pin.y == 0.75)
        #expect(pin.target === pages["Neverwinter"])

        // Summary
        #expect(summary.pages == 5)
        #expect(summary.images == 5)  // three on the hero, two on the world
        #expect(summary.maps == 1)
        #expect(summary.campaigns == 1)
        #expect(summary.links == 3)
        #expect(!summary.skippedAnything)
    }

    @Test func importGivesEveryRecordAFreshID() async throws {
        let source = try makeContext()
        let original = try makeRichWorld(in: source)
        let contents = try roundTrip(original)

        let (imported, _) = await WorldImporter.importWorld(contents, into: source)

        let originalPageIDs = Set((original.pages ?? []).map(\.id))
        let importedPageIDs = Set((imported.pages ?? []).map(\.id))
        #expect(originalPageIDs.isDisjoint(with: importedPageIDs))
        #expect(imported.id != original.id)

        let originalImageIDs = Set((original.pages ?? []).flatMap { $0.sortedImages.map(\.id) })
        let importedImageIDs = Set((imported.pages ?? []).flatMap { $0.sortedImages.map(\.id) })
        #expect(originalImageIDs.isDisjoint(with: importedImageIDs))
    }

    @Test func importingTwiceMakesTwoIndependentWorldsWithDistinctNames() async throws {
        let context = try makeContext()
        let original = try makeRichWorld(in: context)
        let contents = try roundTrip(original)

        let (second, _) = await WorldImporter.importWorld(contents, into: context)
        let (third, _) = await WorldImporter.importWorld(contents, into: context)

        #expect(second.name == "Faerûn (2)")
        #expect(third.name == "Faerûn (3)")
        #expect(try context.fetchCount(FetchDescriptor<World>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 15)

        // Changing one copy leaves the others alone.
        let page = try #require((second.pages ?? []).first { $0.title == "Elf" })
        context.delete(page)
        try context.save()
        #expect((original.pages ?? []).contains { $0.title == "Elf" })
        #expect((third.pages ?? []).contains { $0.title == "Elf" })
    }

    @Test func exportingTheSameWorldTwiceGivesTheSameFile() throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world, exportedAt: date))
        let second = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world, exportedAt: date))

        #expect(first.fileWrappers?["world.json"]?.regularFileContents == second.fileWrappers?["world.json"]?.regularFileContents)
        #expect(first.fileWrappers?["images"]?.fileWrappers?.keys.sorted() == second.fileWrappers?["images"]?.fileWrappers?.keys.sorted())
    }

    @Test func packageLayoutHasWorldJSONAndImageFiles() throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)

        let package = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))

        #expect(package.isDirectory)
        #expect(package.fileWrappers?["world.json"]?.isRegularFile == true)
        let images = try #require(package.fileWrappers?["images"]?.fileWrappers)
        #expect(images.count == 6)  // three page images, two world images and one map
        #expect(images.keys.allSatisfy { $0.hasSuffix(".jpeg") || $0.hasSuffix(".jpg") })
    }

    @Test func aWorldWithNoImagesWritesNoImagesFolder() throws {
        let context = try makeContext()
        let world = World(name: "Plain")
        context.insert(world)

        let package = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))

        #expect(package.fileWrappers?["images"] == nil)
        let contents = try WorldPackage.contents(of: package)
        #expect(contents.archive.world.name == "Plain")
        #expect(contents.files.isEmpty)
    }

    @Test func linksToPagesOutsideTheWorldAreNotExported() throws {
        let context = try makeContext()
        let world = World(name: "A")
        let other = World(name: "B")
        context.insert(world)
        context.insert(other)
        let inside = world.addPage(kind: .character, in: context)
        let outside = other.addPage(kind: .race, in: context)
        inside.setLinkedPage(outside, role: "race", in: context)

        let contents = WorldExporter.makeContents(of: world)

        #expect(contents.archive.links.isEmpty)
    }

    // MARK: Unusual and damaged input

    @Test func unknownKindsAndSystemsSurviveARoundTrip() async throws {
        let context = try makeContext()
        let world = World(name: "Future")
        world.systemRaw = "pathfinder9"
        context.insert(world)
        let page = world.addPage(kind: .item, in: context)
        page.kindRaw = "spaceship"

        let (imported, _) = await WorldImporter.importWorld(try roundTrip(world), into: try makeContext())

        #expect(imported.systemRaw == "pathfinder9")
        #expect(imported.pages?.first?.kindRaw == "spaceship")
    }

    @Test func aMissingImageFileIsSkippedAndTheRestStillImports() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let removed = try #require(contents.files.keys.sorted().first)
        contents.files[removed] = nil

        let (imported, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(summary.skippedImages == 1)
        #expect(summary.pages == 5)
        #expect(imported.pages?.count == 5)
    }

    @Test func anUndecodableImageFileIsSkipped() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let name = try #require(contents.archive.pages.flatMap(\.images).compactMap(\.file).first)
        contents.files[name] = Data("not an image".utf8)

        let (_, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(summary.skippedImages == 1)
        #expect(summary.images == 4)  // two left on the hero, two on the world
    }

    @Test func aFileWithoutWorldImagesStillImports() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = WorldExporter.makeContents(of: world)
        // Files written before world images existed have no `images` key on the world at all.
        contents.archive.world.images = nil

        let reread = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: contents))
        #expect(reread.archive.world.images == nil)

        let (imported, summary) = await WorldImporter.importWorld(reread, into: try makeContext())
        #expect(imported.sortedImages.isEmpty)
        #expect(imported.defaultImage == nil)
        #expect(summary.images == 3)  // the hero's images are unaffected
        #expect(imported.pages?.count == 5)
    }

    @Test func aWorldImageWithAMissingFileIsSkipped() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let name = try #require(contents.archive.world.images?.first?.file)
        contents.files[name] = nil

        let (imported, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(summary.skippedImages == 1)
        #expect(imported.sortedImages.count == 1)
        #expect(imported.sortedImages.filter(\.isDefault).count == 1)
    }

    @Test func linksToMissingPagesAreSkippedAndCounted() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let source = try #require(contents.archive.pages.first?.id)
        contents.archive.links.append(LinkRecord(id: UUID(), role: "ghost", sourceID: source, targetID: UUID()))
        contents.archive.links.append(LinkRecord(id: UUID(), role: "ghost", sourceID: UUID(), targetID: source))

        let (imported, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(summary.skippedLinks == 2)
        #expect(summary.links == 3)
        #expect(summary.skippedAnything)
        #expect(imported.pages?.count == 5)
    }

    @Test func parentLoopsInAFileAreIgnored() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let region = try #require(contents.archive.pages.first { $0.title == "Sword Coast" })
        let town = try #require(contents.archive.pages.first { $0.title == "Neverwinter" })
        // Neverwinter is already inside Sword Coast. Put Sword Coast inside Neverwinter, and a page inside itself.
        let regionIndex = try #require(contents.archive.pages.firstIndex { $0.id == region.id })
        contents.archive.pages[regionIndex].parentID = town.id
        let townIndex = try #require(contents.archive.pages.firstIndex { $0.id == town.id })
        contents.archive.pages[townIndex].parentID = town.id

        let (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())

        // Walking up from any page must terminate.
        for page in imported.pages ?? [] {
            var depth = 0
            var current: Page? = page
            while let next = current?.parent, depth < 100 {
                current = next
                depth += 1
            }
            #expect(depth < 100, "\(page.title) is part of a parent loop")
        }
    }

    @Test func importRepairsMissingAndDuplicateDefaultImages() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        var contents = try roundTrip(world)
        let heroIndex = try #require(contents.archive.pages.firstIndex { $0.title == "Aria Vale" })

        for index in contents.archive.pages[heroIndex].images.indices {
            contents.archive.pages[heroIndex].images[index].isDefault = false
        }
        var (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())
        var hero = try #require((imported.pages ?? []).first { $0.title == "Aria Vale" })
        #expect(hero.sortedImages.filter(\.isDefault).count == 1)
        #expect(hero.sortedImages.first?.isDefault == true)

        for index in contents.archive.pages[heroIndex].images.indices {
            contents.archive.pages[heroIndex].images[index].isDefault = true
        }
        (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())
        hero = try #require((imported.pages ?? []).first { $0.title == "Aria Vale" })
        #expect(hero.sortedImages.filter(\.isDefault).count == 1)
        #expect(hero.sortedImages.first?.isDefault == true)
    }

    @Test func aNewerFormatVersionIsRefused() throws {
        let json = Data(#"{"formatVersion": 99, "somethingNew": true}"#.utf8)
        let package = FileWrapper(directoryWithFileWrappers: ["world.json": FileWrapper(regularFileWithContents: json)])

        #expect(throws: WorldTransferError.self) {
            try WorldPackage.contents(of: package)
        }
        do {
            _ = try WorldPackage.contents(of: package)
        } catch WorldTransferError.newerFormat(let found, let supported) {
            #expect(found == 99)
            #expect(supported == WorldArchive.currentFormatVersion)
        } catch {
            Issue.record("Expected newerFormat, got \(error)")
        }
    }

    @Test func aFolderWithoutWorldJSONIsNotAWorld() throws {
        let empty = FileWrapper(directoryWithFileWrappers: [:])
        let plainFile = FileWrapper(regularFileWithContents: Data("hello".utf8))

        for wrapper in [empty, plainFile] {
            do {
                _ = try WorldPackage.contents(of: wrapper)
                Issue.record("Expected an error")
            } catch WorldTransferError.notAWorldPackage {
                // expected
            } catch {
                Issue.record("Expected notAWorldPackage, got \(error)")
            }
        }
    }

    @Test func corruptJSONIsReportedAsUnreadable() throws {
        let package = FileWrapper(directoryWithFileWrappers: [
            "world.json": FileWrapper(regularFileWithContents: Data("{ this is not json".utf8)),
        ])
        do {
            _ = try WorldPackage.contents(of: package)
            Issue.record("Expected an error")
        } catch WorldTransferError.unreadable {
            // expected
        } catch {
            Issue.record("Expected unreadable, got \(error)")
        }
    }

    @Test func jsonThatIsNotAWorldIsReportedAsUnreadable() throws {
        let json = Data(#"{"formatVersion": 1, "pages": "wrong"}"#.utf8)
        let package = FileWrapper(directoryWithFileWrappers: ["world.json": FileWrapper(regularFileWithContents: json)])
        do {
            _ = try WorldPackage.contents(of: package)
            Issue.record("Expected an error")
        } catch WorldTransferError.unreadable {
            // expected
        } catch {
            Issue.record("Expected unreadable, got \(error)")
        }
    }

    @Test func aFailedReadCreatesNothing() async throws {
        let context = try makeContext()
        let package = FileWrapper(directoryWithFileWrappers: [:])

        #expect(throws: WorldTransferError.self) {
            try WorldPackage.contents(of: package)
        }
        #expect(try context.fetchCount(FetchDescriptor<World>()) == 0)
    }

    // MARK: Names and files

    @Test func uniqueNamesAddTheSmallestFreeNumber() {
        #expect(WorldImporter.uniqueName("A", avoiding: []) == "A")
        #expect(WorldImporter.uniqueName("A", avoiding: ["A"]) == "A (2)")
        #expect(WorldImporter.uniqueName("A", avoiding: ["A", "A (2)"]) == "A (3)")
        #expect(WorldImporter.uniqueName("A", avoiding: ["A", "A (3)"]) == "A (2)")
    }

    @Test func imageFileExtensionsMatchTheEncodedFormat() {
        #expect(["jpeg", "jpg"].contains(ImageProcessing.fileExtension(for: SampleData.solidImage(width: 8, height: 8))))
        #expect(ImageProcessing.fileExtension(for: SampleData.solidImage(width: 8, height: 8, withAlpha: true)) == "png")
        #expect(ImageProcessing.fileExtension(for: Data("nope".utf8)) == "img")
    }

    @Test func thePackageTypeIsDeclaredAndConformsToPackage() {
        #expect(UTType.encounterWorld.identifier == "com.infography.encounter.world")
        #expect(UTType.encounterWorld.conforms(to: .package))
    }

    @Test func theAppsInfoPlistDeclaresThePackageType() throws {
        // Without this declaration the system shows .encounterworld packages as plain folders and the
        // file pickers don't recognise them.
        let app = try #require(Bundle(identifier: "com.infography.encounter"))
        let declarations = try #require(app.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        let declaration = try #require(declarations.first { $0["UTTypeIdentifier"] as? String == "com.infography.encounter.world" })

        let conformsTo = declaration["UTTypeConformsTo"] as? [String] ?? []
        #expect(conformsTo.contains("com.apple.package"))
        let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
        #expect(tags?["public.filename-extension"] as? [String] == ["encounterworld"])
    }

    @Test func theSampleWorldPackageImportsCleanly() async throws {
        // Samples/ sits at the repository root, three levels above this file.
        let sample = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/Saltmarch Coast.encounterworld")

        let contents = try await WorldPackage.read(from: sample)
        let (world, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(world.name == "Saltmarch Coast")
        #expect(world.system == .dnd5e)
        #expect(world.calendar?.months.count == 10)
        #expect(summary.pages == 21)
        #expect(summary.links == 15)
        #expect(summary.maps == 1)
        #expect(summary.campaigns == 1)
        #expect(summary.images == 6)  // five page images and one world image. The map image is separate.
        #expect(world.sortedImages.count == 1)
        #expect(world.defaultImage != nil)
        #expect(!summary.skippedAnything)

        let pages = Dictionary(uniqueKeysWithValues: (world.pages ?? []).map { ($0.title, $0) })
        #expect(pages["Brackwater"]?.parent === pages["Saltmarch Coast"])
        #expect(pages["The Gilded Gull"]?.parent === pages["Brackwater"])
        #expect(pages["Mira Thorne"]?.characterRole == .playable)
        #expect(pages["Mira Thorne"]?.linkedPage(role: "race") === pages["Human"])
        #expect(pages["Mira Thorne"]?.attributeNumber("dnd5e.dexterity") == 17)
        #expect(pages["Mira Thorne"]?.sortedImages.count == 2)
        #expect(pages["Arrival at Brackwater"]?.eventOrigin == .campaign)
        #expect(pages["Arrival at Brackwater"]?.campaign?.name == "Tides of Brackwater")
        #expect(pages["The Great Drowning"]?.eventOrigin == .backstory)
        #expect(world.maps?.first?.pins?.count == 3)

        // Mentions in the notes point at the imported pages, and their links are rebuilt from the text.
        #expect(pages["Brackwater"]?.mentionedPages.map(\.title) == ["Captain Odric Vane", "Harbor Guild", "The Gilded Gull"])
        #expect(pages["Mira Thorne"]?.mentionedPages.map(\.title) == ["Brackwater", "Mistfen", "Pip"])
        #expect(pages["Saltmarch Coast"]?.mentionedPages.map(\.title) == ["Brackwater", "Mistfen"])
        #expect(pages["Lantern of the Drowned"]?.mentionedPages.map(\.title) == ["Old Lighthouse"])
        #expect(Set(pages["Mistfen"]?.backlinks.map(\.source.title) ?? []) == ["Saltmarch Coast", "Mira Thorne", "Grishka the Mist-Hag"])
        let validIDs = Set((world.pages ?? []).map(\.id))
        for page in world.pages ?? [] {
            #expect(Mention.mentionedIDs(in: page.body).allSatisfy(validIDs.contains), "\(page.title) mentions a page that isn't in the world")
        }

        // Every date in the sample must be valid in the sample's own calendar.
        let calendar = try #require(world.calendar)
        for page in world.pages ?? [] {
            for date in [page.startDate, page.endDate].compactMap({ $0 }) {
                #expect(calendar.isValid(date), "\(page.title) has a date outside the calendar")
            }
        }
    }

    @Test func aPackageWrittenToDiskReadsBackAndImports() async throws {
        let context = try makeContext()
        let world = try makeRichWorld(in: context)
        let package = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("Faerûn.encounterworld")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try package.write(to: url, options: .atomic, originalContentsURL: nil)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("world.json").path, isDirectory: &isDirectory))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("images").path, isDirectory: &isDirectory))

        let contents = try await WorldPackage.read(from: url)
        let (imported, summary) = await WorldImporter.importWorld(contents, into: try makeContext())
        #expect(imported.pages?.count == 5)
        #expect(summary.images == 5)  // three on the hero, two on the world
        #expect(!summary.skippedAnything)
    }
}
