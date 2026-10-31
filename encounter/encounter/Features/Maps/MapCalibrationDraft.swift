//
//  MapCalibrationDraft.swift
//  encounter
//

import Foundation

/// A map's calibration being entered: two points marked on the image, and the real distance between them.
/// Where the map sits in the world is worked out behind the scenes. Kept apart from the views so the rules
/// can be tested.
struct MapCalibrationDraft: Equatable {
    struct Point: Equatable {
        /// Where it was marked on the image, in pixels.
        var pixelX: Double?
        var pixelY: Double?

        var isMarked: Bool { pixelX != nil && pixelY != nil }
    }

    var first = Point()
    var second = Point()
    /// The distance between the two points, always in metres.
    var distanceMetres: Double?
    /// The unit the distance is typed in, which depends on the kind of map.
    var unit: DistanceUnit

    init(unit: DistanceUnit = .miles) {
        self.unit = unit
    }

    /// The distance in `unit`, for the field the creator types in.
    var distance: Double? {
        get { distanceMetres.map(unit.value(fromMetres:)) }
        set { distanceMetres = newValue.map(unit.metres(fromValue:)) }
    }

    /// The scale these points give, or nil until both are marked apart from each other and a distance is set.
    var metresPerPixel: Double? {
        guard let ax = first.pixelX, let ay = first.pixelY, let bx = second.pixelX, let by = second.pixelY,
              let distanceMetres
        else { return nil }
        return MapCalibration.metresPerPixel(pixelA: (ax, ay), pixelB: (bx, by), distanceMetres: distanceMetres)
    }

    /// The calibration for a world map of this image height.
    func worldCalibration(imageHeight: Int) -> MapCalibration? {
        guard let ax = first.pixelX, let ay = first.pixelY, let bx = second.pixelX, let by = second.pixelY,
              let distanceMetres
        else { return nil }
        return MapCalibration(pixelA: (ax, ay), pixelB: (bx, by), distanceMetres: distanceMetres, imageHeight: imageHeight)
    }

    /// What is still needed, in words for the creator, or nil if the calibration can be applied.
    var problem: String? {
        if !first.isMarked || !second.isMarked {
            return String(localized: "Click the map to mark both points.")
        }
        if distanceMetres == nil {
            return String(localized: "Enter the distance between the two points.")
        }
        if metresPerPixel == nil {
            return String(localized: "The points must be in different places, and the distance more than zero.")
        }
        return nil
    }
}

extension MapCalibrationDraft {
    /// The calibration for a world or settlement map of this size, or nil until the draft is complete. A
    /// settlement map is centred on `anchor`, the position of its settlement.
    func calibration(kind: MapKind, imageWidth: Int, imageHeight: Int, anchor: GridPoint?) -> MapCalibration? {
        guard let ax = first.pixelX, let ay = first.pixelY, let bx = second.pixelX, let by = second.pixelY,
              let distanceMetres
        else { return nil }
        switch kind {
        case .world:
            return MapCalibration(pixelA: (ax, ay), pixelB: (bx, by), distanceMetres: distanceMetres, imageHeight: imageHeight)
        case .settlement:
            guard let anchor else { return nil }
            return MapCalibration(
                pixelA: (ax, ay), pixelB: (bx, by), distanceMetres: distanceMetres,
                imageWidth: imageWidth, imageHeight: imageHeight, centredOn: anchor
            )
        case .scene:
            return nil
        }
    }
}

/// A scene map's grid being entered: how many squares it has across and down, and how big a square is.
struct SceneGridDraft: Equatable {
    var columns: Int?
    var rows: Int?
    /// The side of a square in feet, which is 5 in the usual rules.
    var squareFeet: Double? = 5

    var squareMetres: Double? { squareFeet.map(DistanceUnit.feet.metres(fromValue:)) }

    /// The calibration for a scene map of this size centred on `anchor`, and whether the grid's shape disagrees with the image's.
    func result(imageWidth: Int, imageHeight: Int, anchor: GridPoint?) -> (calibration: MapCalibration, shapeMismatch: Bool)? {
        guard let columns, let rows, let squareMetres, let anchor else { return nil }
        return MapCalibration.scene(
            columns: columns, rows: rows, squareMetres: squareMetres,
            imageWidth: imageWidth, imageHeight: imageHeight, centredOn: anchor
        )
    }

    func problem(imageWidth: Int, imageHeight: Int, anchor: GridPoint?) -> String? {
        guard let columns, let rows, columns > 0, rows > 0 else {
            return String(localized: "Enter how many squares the map has across and down.")
        }
        guard let squareFeet, squareFeet > 0 else {
            return String(localized: "Enter the size of a square.")
        }
        guard anchor != nil else { return nil }
        if let result = result(imageWidth: imageWidth, imageHeight: imageHeight, anchor: anchor), result.shapeMismatch {
            return String(localized: "The grid’s shape doesn’t match the image’s, so the squares won’t come out square. You can still apply it.")
        }
        return nil
    }
}
