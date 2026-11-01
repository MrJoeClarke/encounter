//
//  WorldMap.swift
//  encounter
//

import Foundation
import SwiftData

/// A map image. A map must be calibrated before places can be put on it, so that a position on it means a
/// position in the world. Places are drawn on the map from their own positions.
@Model
final class WorldMap {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = MapKind.world.rawValue
    @Attribute(.externalStorage)
    var imageData: Data?
    /// Small version for lists.
    var thumbnailData: Data?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    /// How the image lines up with the world's plane, encoded as JSON. Use `calibration`.
    var calibrationData: Data?
    /// For a scene map, how many squares the grid has across and down. Zero otherwise.
    var gridColumns: Int = 0
    var gridRows: Int = 0
    /// A map with no picture: its places are drawn over a plain background. Its size is in `pixelWidth` and
    /// `pixelHeight`, at a metre to a pixel.
    var isVector: Bool = false
    var createdAt: Date = Date()
    var world: World?
    /// The place this map depicts, which lets a place open its own map. A world map has none.
    var place: Page?

    init(name: String, imageData: Data? = nil, kind: MapKind = .world) {
        self.name = name
        self.imageData = imageData
        self.kindRaw = kind.rawValue
    }

    var kind: MapKind {
        get { MapKind(rawValue: kindRaw) ?? .world }
        set { kindRaw = newValue.rawValue }
    }

    var calibration: MapCalibration? {
        get { calibrationData.flatMap { try? JSONDecoder().decode(MapCalibration.self, from: $0) } }
        set { calibrationData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isCalibrated: Bool { calibrationData != nil && calibration != nil }

    /// Whether this is the world map, the map of the world's root place.
    var isWorldMap: Bool { place?.isWorldRoot ?? (kind == .world) }

    /// Settlement and scene maps are centred on the place they show. The world map isn't.
    var needsPlace: Bool { !isWorldMap }

    /// Where the place this map shows is in the world, which settlement and scene maps are centred on.
    var anchorPosition: GridPoint? { place?.geometry?.centre }

    /// Whether the map can be calibrated yet: the world map always can, the others once their place has a position.
    var canBeCalibrated: Bool { !needsPlace || anchorPosition != nil }

    /// Changes whether this is a settlement map or a scene map. The world map can't change, and a map can't
    /// become the world map. A change of kind makes the old calibration (and grid) meaningless.
    func change(to newKind: MapKind) {
        guard newKind != kind, newKind != .world, !isWorldMap else { return }
        kind = newKind
        calibration = nil
        gridColumns = 0
        gridRows = 0
    }
}

/// What happened when a place was put on a map.
enum PlacementResult: Equatable {
    case placed
    case mapNotCalibrated
    /// The spot is off the edge of the world's plane, where positions can't be negative.
    case outsideWorld
    case notAPlace
}

extension WorldMap {
    /// Puts a place at an image position, which sets the place's position in the world.
    @discardableResult
    func position(_ page: Page, atPixelX x: Double, y: Double) -> PlacementResult {
        guard page.kind == .place else { return .notAPlace }
        guard let calibration else { return .mapNotCalibrated }
        let point = calibration.gridPoint(atX: x, y: y)
        guard page.setGeometry(.point(point)) else { return .outsideWorld }
        return .placed
    }

    /// The places to show on this map: those with a position here, except any inside another place that is shown, so
    /// a settlement hides the buildings in it, and they are shown on the settlement's own map instead. A place whose
    /// parent isn't on this map isn't hidden by it. The map's own place isn't shown, and doesn't hide what is in it.
    func visiblePlaces(among places: [Page]) -> [Page] {
        func isOnMap(_ page: Page) -> Bool {
            guard page !== place, !page.isDeleted, let geometry = page.geometry else { return false }
            switch geometry {
            case .polygon, .line: return true
            case .point: return pixel(of: page) != nil
            }
        }
        let shown = places.filter(isOnMap)
        let shownIDs = Set(shown.map(\.id))
        return shown.filter { page in !page.ancestors.contains { shownIDs.contains($0.id) } }
    }

    /// Where a place is on this map's image, or nil if the map isn't calibrated, the place has no position, or
    /// the place is off the edge of the image.
    func pixel(of page: Page) -> (x: Double, y: Double)? {
        guard let calibration, let centre = page.geometry?.centre else { return nil }
        let pixel = calibration.pixel(at: centre)
        guard (0...Double(pixelWidth)).contains(pixel.x), (0...Double(pixelHeight)).contains(pixel.y) else { return nil }
        return pixel
    }
}

extension World {
    /// Adds a map with no picture, which covers `extentMetres` across and up, and is calibrated from the start at a
    /// metre to a pixel. The world map starts at the south-west corner of the plane. A settlement map is centred on
    /// its place, as far as the edge of the plane allows.
    @MainActor
    @discardableResult
    func addVectorMap(named name: String, for place: Page, extentMetres: Double, in context: ModelContext) -> WorldMap? {
        guard extentMetres.isFinite, extentMetres >= 10 else { return nil }
        let size = Int(extentMetres.rounded())
        let map = WorldMap(name: name, kind: place.isWorldRoot ? .world : .settlement)
        map.isVector = true
        map.pixelWidth = size
        map.pixelHeight = size
        var origin = GridPoint(easting: 0, northing: 0)
        if !place.isWorldRoot, let centre = place.geometry?.centre {
            origin = GridPoint(easting: max(0, centre.easting - Double(size) / 2), northing: max(0, centre.northing - Double(size) / 2))
        }
        map.calibration = MapCalibration(anchoringPixel: (0, Double(size)), at: origin, metresPerPixel: 1)
        context.insert(map)
        map.world = self
        map.place = place
        return map
    }

    /// Adds a map of a place, from image data kept at full size so no detail is lost. The map of the root place is
    /// the world map, and any other is a settlement map until it is changed to a scene map. The image is prepared
    /// off the main actor, and nil is returned if it can't be read as an image.
    @MainActor
    @discardableResult
    func addMap(named name: String, from data: Data, for place: Page, in context: ModelContext) async -> WorldMap? {
        guard let prepared = await ImageProcessing.prepareKeepingFullSize(data),
              let size = ImageProcessing.pixelSize(of: prepared.imageData)
        else { return nil }
        let map = WorldMap(name: name, imageData: prepared.imageData, kind: place.isWorldRoot ? .world : .settlement)
        map.thumbnailData = prepared.thumbnailData
        map.pixelWidth = size.width
        map.pixelHeight = size.height
        context.insert(map)
        map.world = self
        map.place = place
        return map
    }
}
