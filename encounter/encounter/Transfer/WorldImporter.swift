//
//  WorldImporter.swift
//  encounter
//

import Foundation
import SwiftData

/// What an import created, and what it had to leave out.
struct ImportSummary: Equatable {
    var worldName = ""
    var pages = 0
    var images = 0
    var maps = 0
    var campaigns = 0
    var links = 0
    /// Links whose source or target page isn't in the file.
    var skippedLinks = 0
    /// Images whose file is missing or can't be decoded.
    var skippedImages = 0

    var skippedAnything: Bool { skippedLinks > 0 || skippedImages > 0 }
}

/// Creates a new world from an archive. Never touches an existing world, and gives every record a fresh ID,
/// so importing the same file twice gives two independent worlds.
enum WorldImporter {
    @discardableResult
    static func importWorld(
        _ contents: WorldPackageContents,
        into context: ModelContext
    ) async -> (world: World, summary: ImportSummary) {
        let archive = contents.archive
        var summary = ImportSummary()

        let existingNames = Set(((try? context.fetch(FetchDescriptor<World>())) ?? []).map(\.name))
        let world = World(name: uniqueName(archive.world.name, avoiding: existingNames), summary: archive.world.summary)
        world.systemRaw = archive.world.system
        world.systemVersion = archive.world.systemVersion ?? 0
        world.systemState = archive.world.systemState ?? [:]
        world.editionRaw = archive.world.edition ?? LibraryEdition.default.rawValue
        context.insert(world)
        summary.worldName = world.name

        if let record = archive.world.calendar, let calendar = world.calendar {
            calendar.hoursPerDay = record.hoursPerDay
            calendar.months = record.months.map { CalendarMonth(name: $0.name, dayCount: $0.dayCount) }
            calendar.weekdays = record.weekdays
        }

        await importImages(archive.world.images ?? [], into: world, files: contents.files, context: context, summary: &summary)

        var campaigns: [UUID: Campaign] = [:]
        for record in archive.campaigns {
            let campaign = Campaign(name: record.name, summary: record.summary)
            campaign.createdAt = record.createdAt
            context.insert(campaign)
            campaign.world = world
            campaigns[record.id] = campaign
            summary.campaigns += 1
        }

        // Create every page first, so parents, links and maps can refer to pages that appear later in the file.
        var pages: [UUID: Page] = [:]
        for record in archive.pages {
            let page = Page(title: record.title, kind: .character)
            page.kindRaw = record.kind
            page.characterRoleRaw = record.characterRole
            page.summary = record.summary
            page.body = record.body
            page.attributes = record.attributes
            page.tags = record.tags
            page.createdAt = record.createdAt
            page.updatedAt = record.updatedAt
            page.eventOriginRaw = record.eventOrigin
            page.startDate = record.startDate
            page.endDate = record.endDate
            page.basedOnKey = record.basedOnKey
            context.insert(page)
            page.world = world
            // A shape that isn't valid on the plane would break the spatial checks, so it is dropped.
            page.geometry = record.geometry.flatMap { $0.isValid && page.kind == .place ? $0 : nil }
            pages[record.id] = page
            summary.pages += 1
        }

        // Mentions in the notes point at the old page IDs. Point them at the new pages, and turn any that
        // point outside the file into plain text.
        let newIDs = pages.mapValues(\.id)

        for record in archive.pages {
            guard let page = pages[record.id] else { continue }
            var body = page.body
            Mention.remapMentions(in: &body, using: newIDs)
            page.body = body
            page.updateSearchText()
            if let parentID = record.parentID, let parent = pages[parentID], !wouldCreateCycle(making: parent, parentOf: page) {
                page.parent = parent
            }
            page.parentSourceRaw = record.parentSource
            if let campaignID = record.campaignID {
                page.campaign = campaigns[campaignID]
            }

            await importImages(record.images, into: page, files: contents.files, context: context, summary: &summary)
        }

        for record in archive.links where record.role != LinkRole.mention {
            guard let source = pages[record.sourceID], let target = pages[record.targetID] else {
                summary.skippedLinks += 1
                continue
            }
            context.insert(PageLink(source: source, target: target, role: record.role))
            summary.links += 1
        }

        // Rebuild the mention links from the notes.
        for page in pages.values {
            MentionSync.sync(page, in: context)
        }

        // The root place comes from the file, or is made now for a file from before there was one.
        world.rootPlaceID = archive.world.rootPlaceID.flatMap { pages[$0]?.id }
        world.ensureRootPlace(in: context)

        for record in archive.maps {
            let map = WorldMap(name: record.name, kind: record.kind.flatMap(MapKind.init(rawValue:)) ?? .world)
            if let file = record.imageFile {
                if let data = contents.files[file] {
                    map.imageData = data
                    if let size = ImageProcessing.pixelSize(of: data) {
                        map.pixelWidth = size.width
                        map.pixelHeight = size.height
                    }
                    map.thumbnailData = await ImageProcessing.prepareKeepingFullSize(data)?.thumbnailData
                } else {
                    summary.skippedImages += 1
                }
            }
            if record.isVector == true, let extent = record.extentMetres {
                map.isVector = true
                map.pixelWidth = extent
                map.pixelHeight = extent
                if let options = record.settlementOptions {
                    map.settlementOptions = options
                } else if let options = record.worldOptions {
                    map.worldOptions = options
                } else if let options = record.sceneOptions {
                    map.sceneOptions = options
                }
            }
            map.calibration = record.calibration
            map.gridColumns = record.gridColumns ?? 0
            map.gridRows = record.gridRows ?? 0
            context.insert(map)
            map.world = world
            map.place = record.placeID.flatMap { pages[$0] } ?? (map.kind == .world ? world.rootPlace : nil)
            summary.maps += 1
        }

        try? context.save()
        return (world, summary)
    }

    /// Adds a page's or world's images, keeping their order, captions and default flag. An image whose file is
    /// missing or can't be decoded is skipped and counted.
    private static func importImages(
        _ records: [ImageRecord],
        into owner: some ImageOwner,
        files: [String: Data],
        context: ModelContext,
        summary: inout ImportSummary
    ) async {
        for record in records {
            guard let file = record.file,
                  let data = files[file],
                  let prepared = await ImageProcessing.prepare(data)
            else {
                summary.skippedImages += 1
                continue
            }
            let image = PageImage(
                imageData: prepared.imageData,
                caption: record.caption,
                sortOrder: record.sortOrder,
                isDefault: record.isDefault
            )
            image.thumbnailData = prepared.thumbnailData
            context.insert(image)
            owner.attach(image)
            summary.images += 1
        }
        owner.ensureSingleDefaultImage()
    }

    /// "Name", then "Name (2)", "Name (3)" and so on, so an imported copy doesn't share a name with an existing world.
    static func uniqueName(_ name: String, avoiding existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        var number = 2
        while existing.contains("\(name) (\(number))") {
            number += 1
        }
        return "\(name) (\(number))"
    }

    /// True if `parent` is `page` or a descendant of it, so making it the parent would create a loop.
    private static func wouldCreateCycle(making parent: Page, parentOf page: Page) -> Bool {
        var current: Page? = parent
        while let ancestor = current {
            if ancestor === page { return true }
            current = ancestor.parent
        }
        return false
    }
}
