//
//  WorldExporter.swift
//  encounter
//

import Foundation
import SwiftData

/// Turns a world into a `WorldPackageContents` snapshot. Runs on the main actor because it reads the models.
enum WorldExporter {
    static func makeContents(of world: World, exportedAt: Date = Date()) -> WorldPackageContents {
        var files: [String: Data] = [:]

        // Stable order, so exporting the same world twice gives the same file.
        let pages = (world.pages ?? []).sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        let pageIDs = Set(pages.map(\.id))

        var pageRecords: [PageRecord] = []
        var linkRecords: [LinkRecord] = []
        for page in pages {
            pageRecords.append(PageRecord(
                id: page.id,
                title: page.title,
                summary: page.summary,
                kind: page.kindRaw,
                characterRole: page.characterRoleRaw,
                body: page.body,
                attributes: page.attributes,
                tags: page.tags,
                createdAt: page.createdAt,
                updatedAt: page.updatedAt,
                eventOrigin: page.eventOriginRaw,
                startDate: page.startDate,
                endDate: page.endDate,
                campaignID: page.campaign?.id,
                parentID: page.parent?.id,
                parentSource: page.parentSourceRaw,
                geometry: page.geometry,
                images: imageRecords(for: page, files: &files),
                basedOnKey: page.basedOnKey
            ))

            for link in page.outgoingLinks ?? [] {
                // Mention links are derived from the notes text, which is exported, so they aren't stored.
                guard link.role != LinkRole.mention,
                      let targetID = link.target?.id, pageIDs.contains(targetID)
                else { continue }
                linkRecords.append(LinkRecord(id: link.id, role: link.role, sourceID: page.id, targetID: targetID))
            }
        }

        let campaignRecords = (world.campaigns ?? [])
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .map { CampaignRecord(id: $0.id, name: $0.name, summary: $0.summary, createdAt: $0.createdAt) }

        let mapRecords = (world.maps ?? [])
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
            .map { map in
                MapRecord(
                    id: map.id,
                    name: map.name,
                    imageFile: map.imageData.map { store($0, id: map.id, in: &files) },
                    kind: map.kindRaw,
                    calibration: map.calibration,
                    gridColumns: map.gridColumns == 0 ? nil : map.gridColumns,
                    gridRows: map.gridRows == 0 ? nil : map.gridRows,
                    placeID: map.place?.id,
                    isVector: map.isVector ? true : nil,
                    extentMetres: map.isVector ? map.pixelWidth : nil,
                    settlementOptions: map.settlementOptions,
                    worldOptions: map.worldOptions,
                    sceneOptions: map.sceneOptions
                )
            }

        let archive = WorldArchive(
            exportedAt: exportedAt,
            world: WorldRecord(
                id: world.id,
                name: world.name,
                summary: world.summary,
                system: world.systemRaw,
                createdAt: world.createdAt,
                calendar: world.calendar.map { calendar in
                    CalendarRecord(
                        hoursPerDay: calendar.hoursPerDay,
                        months: calendar.months.map { MonthRecord(name: $0.name, dayCount: $0.dayCount) },
                        weekdays: calendar.weekdays
                    )
                },
                images: imageRecords(for: world, files: &files),
                edition: world.editionRaw,
                rootPlaceID: world.rootPlaceID,
                systemVersion: world.systemVersion > 0 ? world.systemVersion : nil
            ),
            campaigns: campaignRecords,
            pages: pageRecords,
            links: linkRecords,
            maps: mapRecords
        )
        return WorldPackageContents(archive: archive, files: files)
    }

    private static func imageRecords(for owner: some ImageOwner, files: inout [String: Data]) -> [ImageRecord] {
        owner.sortedImages.map { image in
            ImageRecord(
                id: image.id,
                caption: image.caption,
                sortOrder: image.sortOrder,
                isDefault: image.isDefault,
                file: image.imageData.map { store($0, id: image.id, in: &files) }
            )
        }
    }

    /// Stores image data under `<id>.<extension>` and returns the file name.
    private static func store(_ data: Data, id: UUID, in files: inout [String: Data]) -> String {
        let name = "\(id.uuidString).\(ImageProcessing.fileExtension(for: data))"
        files[name] = data
        return name
    }
}
