//
//  PaperTexture.swift
//  encounter
//

import Foundation
import CoreGraphics

/// The look of the paper a map is drawn on: fine grain, broad mottling, a few stains and darker edges, like old paper. Every part is
/// worked out from where a pixel is in the world, so tiles join without a seam, nothing moves when the map is panned, and the same
/// map always has the same paper. The size of the larger marks follows the size of the map, so they look alike at every zoom.
nonisolated struct PaperTexture: Equatable, Sendable {
    /// How much the finest grain lightens and darkens the paper, as a share of its brightness.
    var grain = 0.035
    /// The same for the broad, cloudy variation, and how many such clouds there are across the map.
    var mottle = 0.07
    var mottleScale = 5.0
    /// How strong the stains are, how many there are across the map, and the colour of the paper in them, as a multiple of its own.
    var stain = 0.08
    var stainScale = 2.2
    var stainTint = (red: 0.82, green: 0.72, blue: 0.55)
    /// How much darker the paper is at the edge of the map, and how far in, as a share of the map's width, the darkening reaches.
    var edge = 0.28
    var edgeReach = 0.12
    /// Changes the paper without changing anything else.
    var seed: UInt64 = 7

    static func == (a: PaperTexture, b: PaperTexture) -> Bool {
        a.grain == b.grain && a.mottle == b.mottle && a.mottleScale == b.mottleScale && a.stain == b.stain
            && a.stainScale == b.stainScale && a.stainTint == b.stainTint && a.edge == b.edge && a.edgeReach == b.edgeReach && a.seed == b.seed
    }

    /// Where the map is, in the plane's metres, so the paper can darken towards its edge and size its marks.
    typealias Area = (minEasting: Double, minNorthing: Double, maxEasting: Double, maxNorthing: Double)

    /// The colour of the paper, as multiples of the plain ground's, at a place in the plane.
    func tint(easting: Double, northing: Double, in map: Area) -> (red: Double, green: Double, blue: Double) {
        let width = max(map.maxEasting - map.minEasting, 1)
        let height = max(map.maxNorthing - map.minNorthing, 1)
        let size = max(width, height)
        let x = (easting - map.minEasting) / size, y = (northing - map.minNorthing) / size

        var light = 1.0
        light += mottle * (Self.noise(x * mottleScale, y * mottleScale, seed) * 2 - 1)
        light += mottle * 0.5 * (Self.noise(x * mottleScale * 3, y * mottleScale * 3, seed &+ 1) * 2 - 1)

        // Stains are where a slow noise passes a threshold, fading in so they have soft edges.
        let cloud = Self.noise(x * stainScale + 11, y * stainScale + 5, seed &+ 2)
        let stained = min(max((cloud - 0.62) / 0.18, 0), 1) * stain / 0.12

        // Darker towards the edge of the map, and beyond it.
        let across = min(easting - map.minEasting, map.maxEasting - easting) / width
        let down = min(northing - map.minNorthing, map.maxNorthing - northing) / height
        let inside = min(across, down)
        let burn = edge * pow(min(max(1 - inside / edgeReach, 0), 1), 2)

        var r = light, g = light, b = light
        r *= 1 - stained * (1 - stainTint.red); g *= 1 - stained * (1 - stainTint.green); b *= 1 - stained * (1 - stainTint.blue)
        // The edge burns brown rather than grey: it takes more blue than red.
        r *= 1 - burn * 0.7; g *= 1 - burn * 0.85; b *= 1 - burn
        return (r, g, b)
    }

    /// The grain at a pixel of a tile: the same for the same pixel of the world at that zoom, whichever tile it is cut into.
    func grain(atPixelX x: Int, y: Int) -> Double {
        let h = Self.hash(UInt64(bitPattern: Int64(x)) &* 73856093 ^ UInt64(bitPattern: Int64(y)) &* 19349663 ^ seed &* 83492791)
        return 1 + grain * (Double(h % 2001) / 1000 - 1)
    }

    /// A tile of paper: `ground` with the texture over it. `area` is the part of the plane the tile covers, and `map` all of the map.
    func tile(ground: (red: Double, green: Double, blue: Double), area: Area, map: Area, size: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let across = (area.maxEasting - area.minEasting) / Double(size)
        let down = (area.maxNorthing - area.minNorthing) / Double(size)
        let originX = Int((area.minEasting / across).rounded()), originY = Int((area.maxNorthing / down).rounded())
        for row in 0..<size {
            let northing = area.maxNorthing - (Double(row) + 0.5) * down
            for column in 0..<size {
                let easting = area.minEasting + (Double(column) + 0.5) * across
                let t = tint(easting: easting, northing: northing, in: map)
                let g = grain(atPixelX: originX + column, y: originY - row)
                let i = (row * size + column) * 4
                pixels[i] = Self.byte(ground.red * t.red * g)
                pixels[i + 1] = Self.byte(ground.green * t.green * g)
                pixels[i + 2] = Self.byte(ground.blue * t.blue * g)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private static func byte(_ value: Double) -> UInt8 { UInt8(min(max(value, 0), 1) * 255) }

    // MARK: Noise

    private static func hash(_ value: UInt64) -> UInt64 {
        var x = value &+ 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }

    /// Smooth noise from 0 to 1, with a feature about one unit across.
    static func noise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func corner(_ dx: Double, _ dy: Double) -> Double {
            let h = hash(UInt64(bitPattern: Int64(x0 + dx)) &* 374761393 ^ UInt64(bitPattern: Int64(y0 + dy)) &* 668265263 ^ seed &* 2246822519)
            return Double(h % 10001) / 10000
        }
        let top = corner(0, 0) * (1 - sx) + corner(1, 0) * sx
        let bottom = corner(0, 1) * (1 - sx) + corner(1, 1) * sx
        return top * (1 - sy) + bottom * sy
    }
}
