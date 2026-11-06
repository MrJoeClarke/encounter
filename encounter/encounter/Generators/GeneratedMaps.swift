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
    /// Whether a settlement can be made of this place. A building is already as small as a settlement gets, so it can only
    /// have scenes.
    var canHaveSettlementMap: Bool { attributeText("core.placeType") != "Building" }

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
        let options = optionsWithMapRiver(options, for: place)
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
        let name = place.title.isEmpty ? String(localized: "Settlement Map") : String(localized: "\(place.title) Map")
        return await applyGenerated(
            generated.features, extent: plan.extent, mapName: name, for: place, in: context, mapKind: .settlement, progress: progress,
            remember: { $0.settlementOptions = options }
        )
    }

    /// Makes the world map from options, as a vector map of the world with a place for the sea, each realm, the forests and
    /// mountains, the rivers and roads, and each settlement. The settlements already on the map are built around, unless
    /// the options say otherwise. Made again, it replaces the places the last run made, except any that have been edited.
    ///
    /// Like a settlement, the layout is worked out away from the main actor and the places are made a few at a time.
    @MainActor
    @discardableResult
    func generateWorld(
        options: WorldOptions, in context: ModelContext, progress: ((_ made: Int, _ total: Int) -> Void)? = nil
    ) async -> GeneratedMapSummary? {
        guard let root = rootPlace else { return nil }
        let fixed = fixedSettlements(excludingUneditedFrom: worldMap)
        guard let generated = await WorldGenerator.generateInBackground(options, fixed: fixed), !Task.isCancelled else { return nil }
        return await applyGenerated(
            generated.features, extent: generated.extent, mapName: String(localized: "\(name) Map"), for: root, in: context, mapKind: .world, progress: progress,
            remember: { $0.worldOptions = options }
        )
    }

    /// Makes the scene map of a place, as a vector map on a grid of 5-foot squares with a place for each room, corridor, door
    /// and staircase. The place needs a position, which the map is centred on. Made again, it replaces the places the last run
    /// made, except any that have been edited.
    @MainActor
    @discardableResult
    func generateScene(
        for place: Page, options: SceneOptions, in context: ModelContext, progress: ((_ made: Int, _ total: Int) -> Void)? = nil
    ) async -> GeneratedMapSummary? {
        guard place.kind == .place, !place.isWorldRoot, place.geometry != nil else { return nil }
        let plan = World.scenePlan(for: place, options: options)
        var effective = SceneGenerator.clamped(options)
        effective.squares = plan.squares
        guard let generated = await SceneGenerator.generateInBackground(effective, outline: plan.outline), !Task.isCancelled else { return nil }
        let name = place.title.isEmpty ? String(localized: "Scene Map") : String(localized: "\(place.title) Scene")
        return await applyGenerated(
            generated.features, extent: generated.extent, mapName: name, for: place, in: context,
            mapKind: .scene, metresPerPixel: SceneOptions.squareMetres / Double(SceneOptions.pixelsPerSquare), progress: progress,
            remember: { map in
                map.sceneOptions = options
                map.gridColumns = plan.squares
                map.gridRows = plan.squares
            }
        )
    }

    /// How big a scene is, and the shape it fills. A building with an outline fills it, and the outline sets the size: the
    /// map is made big enough to hold it, centred on the place, and the outline is given in metres from the map's
    /// south-west corner. Anything else is the size in the options.
    @MainActor
    static func scenePlan(for place: Page, options: SceneOptions) -> (squares: Int, outline: [GridPoint]?) {
        let options = SceneGenerator.clamped(options)
        guard options.kind == .building, options.fitOutline, let drawn = place.drawnOutline, drawn.count >= 3, let centre = place.geometry?.centre
        else { return (options.squares, nil) }
        let squares = SceneGenerator.squares(for: options, outline: drawn, centre: centre)
        let pixels = squares * SceneOptions.pixelsPerSquare
        let metresPerPixel = SceneOptions.squareMetres / Double(SceneOptions.pixelsPerSquare)
        guard let calibration = vectorCalibration(for: place, size: pixels, metresPerPixel: metresPerPixel) else { return (squares, nil) }
        let corner = calibration.gridPoint(atX: 0, y: Double(pixels))
        // A building too big for the biggest scene is shrunk to fit it.
        let half = drawn.map { max(abs($0.easting - centre.easting), abs($0.northing - centre.northing)) }.max() ?? 0
        let room = Double(squares - 4) * SceneOptions.squareMetres / 2
        let scale = half > room && half > 0 ? room / half : 1
        let local = drawn.map {
            GridPoint(
                easting: (centre.easting - corner.easting) + ($0.easting - centre.easting) * scale,
                northing: (centre.northing - corner.northing) + ($0.northing - centre.northing) * scale
            )
        }
        return (squares, local)
    }

    /// The settlements already on the world map that a new world is built around: the pins on it, other than ones the
    /// last generation made and nothing has been done to, since those are about to be replaced.
    @MainActor
    func fixedSettlements(excludingUneditedFrom map: WorldMap?) -> [FixedSettlement] {
        (pages ?? []).compactMap { page -> FixedSettlement? in
            guard page.kind == .place, !page.isDeleted, !page.isWorldRoot, page.attributeText("core.placeType") == "Settlement",
                  case .point(let position)? = page.geometry else { return nil }
            if let map, page.wasGenerated(by: map), page.isUneditedGeneration { return nil }
            return FixedSettlement(name: page.title, kind: .town, position: position)
        }
    }

    /// Makes places for what a generator made, on a vector map of the place: the map it made before if there is one, with
    /// the places from the last run replaced except any that have been edited, linked or written about.
    @MainActor
    private func applyGenerated(
        _ features: [GeneratedFeature], extent: Double, mapName: String, for place: Page, in context: ModelContext,
        mapKind: MapKind, metresPerPixel: Double = 1, progress: ((Int, Int) -> Void)?, remember: (WorldMap) -> Void
    ) async -> GeneratedMapSummary? {
        var summary: GeneratedMapSummary
        if let existing = (maps ?? []).first(where: { $0.place === place && $0.kind == mapKind && $0.isVector && $0.generatorData != nil && !$0.isDeleted }) {
            summary = GeneratedMapSummary(map: existing)
            for page in pages ?? [] where page.wasGenerated(by: existing) && !page.isDeleted {
                if page.isUneditedGeneration {
                    context.delete(page)
                    summary.replaced += 1
                } else {
                    summary.kept += 1
                }
            }
            existing.resizeVector(extentMetres: extent, for: place, metresPerPixel: metresPerPixel)
        } else {
            guard let map = addVectorMap(named: mapName, for: place, extentMetres: extent, kind: mapKind, metresPerPixel: metresPerPixel, in: context) else { return nil }
            summary = GeneratedMapSummary(map: map)
        }
        remember(summary.map)

        // The generator works in metres from the map's south-west corner.
        guard let calibration = summary.map.calibration else { return nil }
        let corner = calibration.gridPoint(atX: 0, y: Double(summary.map.pixelHeight))
        func world(_ point: GridPoint) -> GridPoint { GridPoint(easting: corner.easting + point.easting, northing: corner.northing + point.northing) }

        let total = features.count
        progress?(0, total)
        for (index, feature) in features.enumerated() {
            let page = addPage(kind: .place, in: context)
            page.title = feature.name
            page.summary = feature.summary
            page.attributes["core.placeType"] = .text(feature.placeType)
            // What kind of one it is (a city, a castle), which gives its pin.
            if !feature.kind.isEmpty { page.attributes["gen.kind"] = .text(feature.kind) }
            // Which realm of the options a region is, so a settlement in it can use the realm's languages.
            if feature.kind.hasPrefix("realm "), let number = Int(feature.kind.dropFirst("realm ".count)) { page.attributes["gen.realm"] = .number(Double(number)) }
            switch feature.shape {
            case .polygon(let points):
                page.geometry = feature.otherParts.isEmpty ? .polygon(points.map(world)) : .multiPolygon(([points] + feature.otherParts).map { $0.map(world) })
            case .line(let points): page.geometry = .line(points.map(world))
            case .point(let point): page.geometry = .point(world(point))
            }
            // Everything is a part of the place the map is of. The creator chose this parent in effect, so a place the
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
        get { isWorldMap || kind == .scene ? nil : generatorData.flatMap { try? JSONDecoder().decode(SettlementOptions.self, from: $0) } }
        set { generatorData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The options a generated world map was made from, kept so it can be made again.
    var worldOptions: WorldOptions? {
        get { isWorldMap ? generatorData.flatMap { try? JSONDecoder().decode(WorldOptions.self, from: $0) } : nil }
        set { generatorData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The options a generated scene map was made from, kept so it can be made again.
    var sceneOptions: SceneOptions? {
        get { !isWorldMap && kind == .scene ? generatorData.flatMap { try? JSONDecoder().decode(SceneOptions.self, from: $0) } : nil }
        set { generatorData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Changes the size of a vector map, keeping it centred on its place as far as the plane allows.
    @MainActor
    func resizeVector(extentMetres: Double, for place: Page, metresPerPixel: Double = 1) {
        let size = Int((extentMetres / metresPerPixel).rounded())
        pixelWidth = size
        pixelHeight = size
        calibration = World.vectorCalibration(for: place, size: size, metresPerPixel: metresPerPixel)
    }
}

extension Page {
    /// The languages of the realm this place lies in on the world map, if it lies in one the world generator made.
    @MainActor
    var realmLanguages: [LanguageWeight]? {
        guard let world, let map = world.worldMap, let options = map.worldOptions, let spot = geometry?.centre else { return nil }
        let point = V(x: spot.easting, y: spot.northing)
        for region in world.pages ?? [] where !region.isDeleted && region.wasGenerated(by: map) {
            guard let number = region.attributeNumber("gen.realm"),
                  (region.geometry?.outlines ?? []).contains(where: { Plane.contains($0.map { V(x: $0.easting, y: $0.northing) }, point) }) else { continue }
            return options.languages(forRealm: Int(number))
        }
        return nil
    }
}

extension World {
    /// How far from the middle of a settlement the world map's river may pass and still be its river: the settlement's own radius.
    @MainActor
    static func settlementRadius(for place: Page, options: SettlementOptions) -> Double {
        if let drawn = place.drawnOutline, drawn.count >= 3 { return (PlaceGeometry.polygon(drawn).area / .pi).squareRoot() }
        return options.size.radius
    }

    /// The river on the world map that runs through or beside a place, if any: the nearest river place whose line passes within
    /// `radius` of the place's middle. Its stretch near the place is given as points in metres east and north of that middle,
    /// reaching out to `extent` so it crosses the whole of the settlement's map, with the river's name.
    /// The options with the world map's river for this place taken as the settlement's own, or, where the world map has none, with
    /// any taken before let go.
    @MainActor
    func optionsWithMapRiver(_ options: SettlementOptions, for place: Page) -> SettlementOptions {
        var made = options
        let extent = SettlementGenerator.extent(for: options, outline: place.drawnOutline)
        made.useMapRiver(riverNear(place, radius: Self.settlementRadius(for: place, options: options), extent: extent))
        return made
    }

    @MainActor
    func riverNear(_ place: Page, radius: Double, extent: Double) -> (name: String, path: [GridPoint])? {
        guard let middle = place.geometry?.centre else { return nil }
        let here = SettlementGenerator.V(x: middle.easting, y: middle.northing)
        var best: (page: Page, line: [SettlementGenerator.V], distance: Double)?
        for page in pages ?? [] where page.kind == .place && !page.isDeleted && page !== place && page.attributeText("core.placeType") == "River" {
            guard case .line(let points)? = page.geometry, points.count >= 2 else { continue }
            let line = points.map { SettlementGenerator.V(x: $0.easting, y: $0.northing) }
            let distance = SettlementGenerator.distance(from: here, toPolyline: line)
            if distance <= radius, distance < (best?.distance ?? .infinity) { best = (page, line, distance) }
        }
        guard let best else { return nil }
        // Walk the river in small steps, keeping the stretch that lies near the settlement and joins on to the point nearest its middle.
        let step = max(extent / 80, 2)
        var dense: [SettlementGenerator.V] = []
        for (a, b) in zip(best.line, best.line.dropFirst()) {
            let count = max(1, Int((a.distance(to: b) / step).rounded(.up)))
            for i in 0..<count { dense.append(a + (b - a) * (Double(i) / Double(count))) }
        }
        if let last = best.line.last { dense.append(last) }
        let reach = extent * 0.9
        func near(_ p: SettlementGenerator.V) -> Bool { abs(p.x - here.x) <= reach && abs(p.y - here.y) <= reach }
        guard let closest = dense.indices.min(by: { dense[$0].distance(to: here) < dense[$1].distance(to: here) }) else { return nil }
        var low = closest, high = closest
        while low > 0, near(dense[low - 1]) { low -= 1 }
        while high < dense.count - 1, near(dense[high + 1]) { high += 1 }
        // One more point each way, so the line goes on past the edge of the map and is cut there.
        if low > 0 { low -= 1 }
        if high < dense.count - 1 { high += 1 }
        let path = dense[low...high].map { GridPoint(easting: $0.x - here.x, northing: $0.y - here.y) }
        guard path.count >= 2 else { return nil }
        return (best.page.title, path)
    }
}
