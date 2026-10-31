//
//  WebMercator.swift
//  encounter
//

import Foundation
import CoreLocation

/// Treats the world's flat plane of metres as the Web Mercator plane that map tiles use (EPSG:3857), so the plane's
/// easting is the Mercator x and its northing is the Mercator y. Near the equator, where the plane sits, distances
/// are very nearly true, and it lets MapKit show a flat map from tiles cut from the image.
nonisolated enum WebMercator {
    /// The radius of the sphere Web Mercator is defined on, in metres.
    static let radius = 6_378_137.0
    /// Metres around the whole world, which is the width of the tile grid at zoom 0.
    static let worldSize = 2 * Double.pi * radius
    static let tileSize = 512.0

    static func coordinate(easting: Double, northing: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (2 * atan(exp(northing / radius)) - .pi / 2) * 180 / .pi,
            longitude: easting / radius * 180 / .pi
        )
    }

    static func coordinate(_ point: GridPoint) -> CLLocationCoordinate2D {
        coordinate(easting: point.easting, northing: point.northing)
    }

    static func point(_ coordinate: CLLocationCoordinate2D) -> GridPoint {
        GridPoint(
            easting: coordinate.longitude * .pi / 180 * radius,
            northing: log(tan(.pi / 4 + coordinate.latitude * .pi / 180 / 2)) * radius
        )
    }

    /// Metres a tile covers on each side at a zoom level.
    static func tileMetres(zoom: Int) -> Double {
        worldSize / pow(2, Double(zoom))
    }

    /// The plane area a tile covers. Tiles are numbered from the top left of the world, which is at
    /// -π R easting and π R northing.
    static func bounds(zoom: Int, x: Int, y: Int) -> (minEasting: Double, minNorthing: Double, maxEasting: Double, maxNorthing: Double) {
        let size = tileMetres(zoom: zoom)
        let minE = -worldSize / 2 + Double(x) * size
        let maxN = worldSize / 2 - Double(y) * size
        return (minE, maxN - size, minE + size, maxN)
    }

    /// The tile zoom at which one tile pixel is no more than `metresPerPixel`, so a map with that resolution
    /// isn't blurred. Clamped to the zooms MapKit can show.
    static func zoom(forMetresPerPixel metresPerPixel: Double) -> Int {
        guard metresPerPixel > 0, metresPerPixel.isFinite else { return 0 }
        let zoom = log2(worldSize / (tileSize * metresPerPixel)).rounded(.up)
        return Int(min(max(zoom, 0), 21))
    }
}
