//
//  GeneratedMaps.swift
//  encounter
//

import Foundation
import SwiftData

/// What generating a map did.
struct GeneratedMapSummary {
    let map: WorldMap
    /// Places made now.
    var created = 0
    /// Places from an earlier generation that were removed, because nothing had been done to them.
    var replaced = 0
    /// Places from an earlier generation that were kept, because they have been edited, linked or written about.
    var kept = 0
}

extension Page {
    /// A fingerprint of what a generator made: the name, summary, type and shape. If it has changed, the creator has
    /// edited the place.
    private var generationFingerprint: String {
        var hash: UInt64 = 0xcbf29ce484222325
        let text = "\(title)|\(summary)|\(attributeText("core.placeType"))|"
        for byte in Array(text.utf8) + Array(geometryData ?? Data()) {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// Marks a place as made by the generator that made a map, so it can be replaced when the map is made again.
    func markGenerated(by map: WorldMap) {
        attributes["gen.map"] = .text(map.id.uuidString)
        attributes["gen.fingerprint"] = .text(generationFingerprint)
    }

    /// Whether this was made by the generator of `map`.
    func wasGenerated(by map: WorldMap) -> Bool { attributeText("gen.map") == map.id.uuidString }

    /// Whether a generated place is just as it was made: not renamed or moved, nothing written about it, nothing
    /// linked to it or from it, and nothing inside it that the creator added.
    var isUneditedGeneration: Bool {
        attributeText("gen.fingerprint") == generationFingerprint
            && String(body.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (incomingLinks ?? []).allSatisfy(\.isDeleted)
            && (outgoingLinks ?? []).allSatisfy(\.isDeleted)
            && (children ?? []).allSatisfy(\.isDeleted)
            && (maps ?? []).isEmpty
    }
}

extension Page {
    /// The outline the creator drew for this place on the map above, if it has one.
    var drawnOutline: [GridPoint]? {
        if case .polygon(let corners)? = geometry { corners } else { nil }
    }
}

extension World {
    /// What a settlement is made from for a place: how big its map is, and its outline in metres from the map's
    /// south-west corner if the place has been outlined. Without an outline the settlement makes its own edge.
    @MainActor
    static func settlementPlan(for place: Page, options: SettlementOptions) -> (extent: Double, outline: [GridPoint]?) {
        let drawn = place.drawnOutline
        let extent = SettlementGenerator.extent(for: options, outline: drawn)
        guard let drawn, let calibration = vectorCalibration(for: place, size: Int(extent.rounded())) else { return (extent, nil) }
        let corner = calibration.gridPoint(atX: 0, y: extent.rounded())
        return (extent, drawn.map { GridPoint(easting: $0.easting - corner.easting, northing: $0.northing - corner.northing) })
    }

    /// Makes the map of a settlement from options, as a vector map with a place for everything on it: districts and
    /// buildings, streets, the wall and the river. The settlement needs a position on the world map to centre the map
    /// on. If the place has an outline, the settlement fills it. Made again for the same place, it replaces the places the
    /// last run made, except any that have been edited.
    ///
    /// The layout is worked out on a background thread. The places are made on the main actor, since they belong to its
    /// context, a few at a time with the screen given a turn in between, and `progress` is told how many are made.
    /// Once the places start being made the work can't be cancelled, so a half-made settlement is never left behind.
    @MainActor
    @discardableResult
    func generateSettlement(
        for place: Page, options: SettlementOptions, in context: ModelContext, progress: ((_ made: Int, _ total: Int) -> Void)? = nil
    ) async -> GeneratedMapSummary? {
        guard place.kind == .place, !place.isWorldRoot, place.geometry != nil else { return nil }
        let plan = World.settlementPlan(for: place, options: options)
        guard let generated = await SettlementGenerator.generateInBackground(options, outline: plan.outline, extent: plan.extent), !Task.isCancelled else { return nil }
        return await applySettlement(generated, plan: plan, for: place, options: options, in: context, progress: progress)
    }

    /// Puts a generated settlement into the world. See `generateSettlement`.
    @MainActor
    private func applySettlement(
        _ generated: GeneratedSettlement, plan: (extent: Double, outline: [GridPoint]?), for place: Page, options: SettlementOptions,
        in context: ModelContext, progress: ((Int, Int) -> Void)?
    ) async -> GeneratedMapSummary? {
        var summary: GeneratedMapSummary
        if let existing = (maps ?? []).first(where: { $0.place === place && $0.isVector && $0.generatorData != nil && !$0.isDeleted }) {
            summary = GeneratedMapSummary(map: existing)
            for page in pages ?? [] where page.wasGenerated(by: existing) && !page.isDeleted {
                if page.isUneditedGeneration {
                    context.delete(page)
                    summary.replaced += 1
                } else {
                    summary.kept += 1
                }
            }
            existing.resizeVector(extentMetres: plan.extent, for: place)
        } else {
            let name = place.title.isEmpty ? String(localized: "Settlement Map") : String(localized: "\(place.title) Map")
            guard let map = addVectorMap(named: name, for: place, extentMetres: plan.extent, in: context) else { return nil }
            summary = GeneratedMapSummary(map: map)
        }
        summary.map.settlementOptions = options

        // The generator works in metres from the map's south-west corner.
        guard let calibration = summary.map.calibration else { return nil }
        let corner = calibration.gridPoint(atX: 0, y: Double(summary.map.pixelHeight))
        func world(_ point: GridPoint) -> GridPoint { GridPoint(easting: corner.easting + point.easting, northing: corner.northing + point.northing) }

        let total = generated.features.count
        progress?(0, total)
        for (index, feature) in generated.features.enumerated() {
            let page = addPage(kind: .place, in: context)
            page.title = feature.name
            page.summary = feature.summary
            page.attributes["core.placeType"] = .text(feature.placeType)
            switch feature.shape {
            case .polygon(let points): page.geometry = .polygon(points.map(world))
            case .line(let points): page.geometry = .line(points.map(world))
            }
            // Everything is a part of the settlement. The creator chose this parent in effect, so a place the
            // outlines happen to enclose doesn't take another.
            page.parent = place
            page.parentSource = .manual
            page.markGenerated(by: summary.map)
            page.updateSearchText()
            summary.created += 1
            // Let the screen draw now and then, so the progress shows and nothing seems stuck.
            if (index + 1) % 25 == 0 {
                progress?(index + 1, total)
                await Task.yield()
            }
        }
        progress?(total, total)
        return summary
    }
}

extension WorldMap {
    /// The options a generated settlement map was made from, kept so it can be made again.
    var settlementOptions: SettlementOptions? {
        get { generatorData.flatMap { try? JSONDecoder().decode(SettlementOptions.self, from: $0) } }
        set { generatorData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Changes the size of a vector map, keeping it centred on its place as far as the plane allows.
    @MainActor
    func resizeVector(extentMetres: Double, for place: Page) {
        let size = Int(extentMetres.rounded())
        pixelWidth = size
        pixelHeight = size
        calibration = World.vectorCalibration(for: place, size: size)
    }
}
