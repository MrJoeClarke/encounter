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
}

extension World {
    /// Adds a map from image data, kept at full size so no detail is lost. The image is prepared off the main
    /// actor, and nil is returned if it can't be read as an image.
    @MainActor
    @discardableResult
    func addMap(named name: String, from data: Data, kind: MapKind = .world, in context: ModelContext) async -> WorldMap? {
        guard let prepared = await ImageProcessing.prepareKeepingFullSize(data),
              let size = ImageProcessing.pixelSize(of: prepared.imageData)
        else { return nil }
        let map = WorldMap(name: name, imageData: prepared.imageData, kind: kind)
        map.thumbnailData = prepared.thumbnailData
        map.pixelWidth = size.width
        map.pixelHeight = size.height
        context.insert(map)
        map.world = self
        return map
    }
}
