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

    /// The distance in the app's unit (miles), for the field the creator types in.
    var distance: Double? {
        get { distanceMetres.map(DistanceUnit.preferred.value(fromMetres:)) }
        set { distanceMetres = newValue.map(DistanceUnit.preferred.metres(fromValue:)) }
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
