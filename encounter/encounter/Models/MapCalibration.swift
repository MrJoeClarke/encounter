//
//  MapCalibration.swift
//  encounter
//

import Foundation

/// What a map depicts, which decides how it is calibrated.
enum MapKind: String, Codable, CaseIterable, Identifiable {
    /// The whole world, calibrated by marking two points and typing the distance between them.
    case world
    /// A settlement, centred on its place and calibrated by marking two points and typing the distance between them.
    case settlement
    /// A building or battle scene, centred on its place and sized by a grid of squares.
    case scene

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .world: "World Map"
        case .settlement: "Settlement Map"
        case .scene: "Scene Map"
        }
    }

    var systemImage: String {
        switch self {
        case .world: "globe.europe.africa"
        case .settlement: "building.2"
        case .scene: "square.grid.3x3"
        }
    }
}

/// How a map's image lines up with the world's flat plane of metres (eastings and northings, as in
/// `GridPoint`). Image positions are pixels from the top left, with y running down.
///
/// This is the one form every kind of map ends up with, however it was calibrated, so a position on any map
/// means the same place in the world.
nonisolated struct MapCalibration: Codable, Hashable, Sendable {
    /// The plane position of the image's top left corner. Not a `GridPoint` check: a map can reach past the
    /// edge of the plane even though places can't.
    var originEasting: Double
    var originNorthing: Double
    /// How many metres one pixel covers.
    var metresPerPixel: Double
    /// How far the map is turned anticlockwise from north being straight up the image, in radians.
    var rotation: Double

    init(originEasting: Double, originNorthing: Double, metresPerPixel: Double, rotation: Double = 0) {
        self.originEasting = originEasting
        self.originNorthing = originNorthing
        self.metresPerPixel = metresPerPixel
        self.rotation = rotation
    }

    /// How many metres a pixel covers, from two points marked on the image and the real distance between them.
    /// Nil if the points are the same, or the distance isn't a positive, real number.
    static func metresPerPixel(pixelA: (x: Double, y: Double), pixelB: (x: Double, y: Double), distanceMetres: Double) -> Double? {
        let imageLength = hypot(pixelB.x - pixelA.x, pixelB.y - pixelA.y)
        guard imageLength > 0, imageLength.isFinite, distanceMetres > 0, distanceMetres.isFinite else { return nil }
        return distanceMetres / imageLength
    }

    /// A world map, from two points marked on it and the distance between them. The map has north up and sits
    /// with its bottom left corner at the plane's origin, so everything on it has a position of zero or more.
    init?(pixelA: (x: Double, y: Double), pixelB: (x: Double, y: Double), distanceMetres: Double, imageHeight: Int) {
        guard let scale = Self.metresPerPixel(pixelA: pixelA, pixelB: pixelB, distanceMetres: distanceMetres), imageHeight > 0
        else { return nil }
        self.init(anchoringPixel: (0, Double(imageHeight)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: scale)
    }

    /// A settlement map, from two points marked on it and the distance between them. The map is north up and its
    /// centre sits at the settlement's position in the world.
    init?(
        pixelA: (x: Double, y: Double), pixelB: (x: Double, y: Double), distanceMetres: Double,
        imageWidth: Int, imageHeight: Int, centredOn place: GridPoint
    ) {
        guard let scale = Self.metresPerPixel(pixelA: pixelA, pixelB: pixelB, distanceMetres: distanceMetres),
              imageWidth > 0, imageHeight > 0
        else { return nil }
        self.init(anchoringPixel: (Double(imageWidth) / 2, Double(imageHeight) / 2), at: place, metresPerPixel: scale)
    }

    /// A scene map, from the number of squares across and down its grid and how big a square is. The map is
    /// north up and its centre sits at the position of the place it shows. `shapeMismatch` is true when the image
    /// is noticeably a different shape from the grid, so the squares would not come out square.
    static func scene(
        columns: Int, rows: Int, squareMetres: Double, imageWidth: Int, imageHeight: Int, centredOn place: GridPoint
    ) -> (calibration: MapCalibration, shapeMismatch: Bool)? {
        guard columns > 0, rows > 0, squareMetres > 0, squareMetres.isFinite, imageWidth > 0, imageHeight > 0,
              let calibration = MapCalibration(
                anchoringPixel: (Double(imageWidth) / 2, Double(imageHeight) / 2), at: place,
                metresPerPixel: squareMetres * Double(columns) / Double(imageWidth)
              )
        else { return nil }
        let impliedRows = Double(imageHeight) * calibration.metresPerPixel / squareMetres
        return (calibration, abs(impliedRows - Double(rows)) / Double(rows) > 0.05)
    }

    /// A calibration where the plane position `grid` sits at the image's pixel `pixel`, with the given scale and
    /// turn. For maps that are centred on a place.
    init?(anchoringPixel pixel: (x: Double, y: Double), at grid: GridPoint, metresPerPixel: Double, rotation: Double = 0) {
        guard metresPerPixel > 0, metresPerPixel.isFinite, grid.easting.isFinite, grid.northing.isFinite else { return nil }
        let (cornerE, cornerN) = Self.turned(x: pixel.x, y: -pixel.y, by: rotation, scale: metresPerPixel)
        self.init(
            originEasting: grid.easting - cornerE,
            originNorthing: grid.northing - cornerN,
            metresPerPixel: metresPerPixel,
            rotation: rotation
        )
    }

    /// Where an image position is in the world.
    func gridPoint(atX x: Double, y: Double) -> GridPoint {
        let (e, n) = Self.turned(x: x, y: -y, by: rotation, scale: metresPerPixel)
        return GridPoint(easting: originEasting + e, northing: originNorthing + n)
    }

    /// Where a world position is on the image. Outside the image's own area the result lies off its edges.
    func pixel(at point: GridPoint) -> (x: Double, y: Double) {
        let (x, up) = Self.turned(x: point.easting - originEasting, y: point.northing - originNorthing, by: -rotation, scale: 1 / metresPerPixel)
        return (x, -up)
    }

    /// Metres between two image positions.
    func distance(fromX x1: Double, y y1: Double, toX x2: Double, y y2: Double) -> Double {
        hypot(x2 - x1, y2 - y1) * metresPerPixel
    }

    private static func turned(x: Double, y: Double, by angle: Double, scale: Double) -> (Double, Double) {
        (scale * (x * cos(angle) - y * sin(angle)), scale * (x * sin(angle) + y * cos(angle)))
    }
}
