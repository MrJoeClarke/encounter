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
    var grain = 0.04
    /// The same for the broad, cloudy variation, and how many such clouds there are across the map.
    var mottle = 0.045
    var mottleScale = 5.0
    /// How strong the stains are, how many there are across the map, and the colour of the paper in them, as a multiple of its own.
    var stain = 0.045
    var stainScale = 6.0
    var stainTint = (red: 0.82, green: 0.72, blue: 0.55)
    /// How much darker the paper is at the edge of the map, and how far in, as a share of the map's width, the darkening reaches.
    var edge = 0.22
    var edgeReach = 0.06
    /// How much the crumple (at about 300, 80 and 20 screen pixels) and the fibres (at about 6) vary the paper. These are sized by
    /// the screen, not the map, so there is texture to see at every zoom.
    var crumple = 0.035
    var fibre = 0.03
    /// Changes the paper without changing anything else.
    var seed: UInt64 = 7

    static func == (a: PaperTexture, b: PaperTexture) -> Bool {
        a.grain == b.grain && a.mottle == b.mottle && a.mottleScale == b.mottleScale && a.stain == b.stain
            && a.stainScale == b.stainScale && a.crumple == b.crumple && a.fibre == b.fibre && a.stainTint == b.stainTint && a.edge == b.edge && a.edgeReach == b.edgeReach && a.seed == b.seed
    }

    /// Where the map is, in the plane's metres, so the paper can darken towards its edge and size its marks.
    typealias Area = (minEasting: Double, minNorthing: Double, maxEasting: Double, maxNorthing: Double)

    /// The colour of the paper, as multiples of the plain ground's, at a place in the plane.
    func tint(easting: Double, northing: Double, in map: Area, metresPerPixel: Double = 0) -> (red: Double, green: Double, blue: Double) {
        let width = max(map.maxEasting - map.minEasting, 1)
        let height = max(map.maxNorthing - map.minNorthing, 1)
        let size = max(width, height)
        let x = (easting - map.minEasting) / size, y = (northing - map.minNorthing) / size

        var light = 1.0
        light += mottle * (Self.noise(x * mottleScale, y * mottleScale, seed) * 2 - 1)
        light += mottle * 0.5 * (Self.noise(x * mottleScale * 3, y * mottleScale * 3, seed &+ 1) * 2 - 1)

        // Texture sized by the screen: broad crumpling, then finer, then the fibres of the paper.
        if metresPerPixel > 0 {
            func layer(_ pixels: Double, _ salt: UInt64) -> Double {
                Self.noise(easting / (metresPerPixel * pixels), northing / (metresPerPixel * pixels), seed &+ salt) * 2 - 1
            }
            light += crumple * (layer(300, 10) + 0.8 * layer(80, 11) + 0.6 * layer(20, 12)) / 1.8
            light += fibre * (layer(6, 13) + 0.7 * layer(2.5, 14)) / 1.4
        }

        // Stains are where a slow noise passes a threshold, fading in so they have soft edges.
        // The edge is a little rough and fairly sharp, like a water mark.
        let cloud = Self.noise(x * stainScale + 11, y * stainScale + 5, seed &+ 2) + 0.05 * (Self.noise(x * stainScale * 7, y * stainScale * 7, seed &+ 3) - 0.5)
        let stained = min(max((cloud - 0.7) / 0.16, 0), 1) * stain / 0.12

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

    /// The size, in pixels, after which the fine look of the paper repeats. Its layers are 240, 80, 20, 6 and 2.5 pixels across, which
    /// all go into it a whole number of times.
    static let finePeriod = 480

    nonisolated(unsafe) private static var fineKept: [String: [Float]] = [:]
    private static let fineLock = NSLock()

    /// Makes the picture of the fine look now, if it hasn't been, so the first tile asked for doesn't have to wait for it. Safe to call
    /// from anywhere, and any number of times.
    func prepare() { _ = fineLook() }

    /// A grid of random numbers from 0 to 1 that the fine layers are smooth noise between, `wrap` across and wrapping round.
    private static func lattice(wrap: Int, salt: UInt64) -> [Double] {
        (0..<(wrap * wrap)).map { i in
            Double(hash(UInt64(i % wrap) &* 374761393 ^ UInt64(i / wrap) &* 668265263 ^ salt &* 2246822519) % 10001) / 10000
        }
    }

    /// Smooth noise between the numbers of a lattice that wraps round, at a place measured in cells.
    @inline(__always)
    private static func smooth(_ table: [Double], wrap: Int, _ x: Double, _ y: Double) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let ix = ((Int(x0) % wrap) + wrap) % wrap, iy = ((Int(y0) % wrap) + wrap) % wrap
        let jx = (ix + 1) % wrap, jy = (iy + 1) % wrap
        let top = table[iy * wrap + ix] * (1 - sx) + table[iy * wrap + jx] * sx
        let bottom = table[jy * wrap + ix] * (1 - sx) + table[jy * wrap + jx] * sx
        return top * (1 - sy) + bottom * sy
    }

    /// How much lighter or darker the crumpling and fibres of the paper make each pixel, over a square of `finePeriod` pixels that
    /// repeats without a seam, made once for a seed. They are sized by the screen, not the map, so one picture serves every zoom. Whoever
    /// asks first makes it, and the others wait for it rather than each making their own.
    func fineLook() -> [Float] {
        let key = "\(seed)|\(crumple)|\(fibre)"
        Self.fineLock.lock()
        defer { Self.fineLock.unlock() }
        if let kept = Self.fineKept[key] { return kept }
        let period = Self.finePeriod
        // Each layer is smooth noise over a lattice that wraps after a whole number of cells, so the picture repeats without a seam.
        let layers: [(wavelength: Double, salt: UInt64)] = [(240, 10), (80, 11), (20, 12), (6, 13), (2.5, 14)]
        let tables = layers.map { layer -> (wrap: Int, wavelength: Double, table: [Double]) in
            let wrap = Int((Double(period) / layer.wavelength).rounded())
            return (wrap, layer.wavelength, Self.lattice(wrap: wrap, salt: seed &+ layer.salt))
        }
        var look = [Float](repeating: 0, count: period * period)
        for y in 0..<period {
            for x in 0..<period {
                let fx = Double(x), fy = Double(y)
                func layer(_ i: Int) -> Double { Self.smooth(tables[i].table, wrap: tables[i].wrap, fx / tables[i].wavelength, fy / tables[i].wavelength) * 2 - 1 }
                let crumpled = crumple * (layer(0) + 0.8 * layer(1) + 0.6 * layer(2)) / 2.4
                let fibres = fibre * (layer(3) + 0.7 * layer(4)) / 1.7
                look[y * period + x] = Float(crumpled + fibres)
            }
        }
        Self.fineKept[key] = look
        return look
    }

    /// A tile of paper: `ground` with the texture over it. `area` is the part of the plane the tile covers, and `map` all of the map.
    /// The broad look (mottling, stains, the burnt edge) is worked out every sixteen pixels and filled in between, since it changes
    /// slowly; the fine look is looked up; only the grain is worked out for each pixel.
    func tile(ground: (red: Double, green: Double, blue: Double), surround: (red: Double, green: Double, blue: Double)? = nil, area: Area, map: Area, size: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let across = (area.maxEasting - area.minEasting) / Double(size)
        let down = (area.maxNorthing - area.minNorthing) / Double(size)
        let originX = Int((area.minEasting / across).rounded()), originY = Int((area.maxNorthing / down).rounded())
        let step = 16
        let points = size / step + 1
        var broad = [Double](repeating: 1, count: points * points * 3)
        for gy in 0..<points {
            for gx in 0..<points {
                let t = tint(easting: area.minEasting + Double(gx * step) * across, northing: area.maxNorthing - Double(gy * step) * down, in: map)
                let i = (gy * points + gx) * 3
                broad[i] = t.red; broad[i + 1] = t.green; broad[i + 2] = t.blue
            }
        }
        let fine = fineLook()
        let period = Self.finePeriod
        for row in 0..<size {
            let northing = area.maxNorthing - (Double(row) + 0.5) * down
            let fy = Double(row) / Double(step)
            let gy = min(Int(fy), points - 2), ty = fy - Double(gy)
            let lookRow = (((originY - row) % period) + period) % period * period
            for column in 0..<size {
                let easting = area.minEasting + (Double(column) + 0.5) * across
                let g = grain(atPixelX: originX + column, y: originY - row)
                let i = (row * size + column) * 4
                // Beyond the edge of the sheet is whatever it lies on, with only the grain.
                if let surround, easting < map.minEasting || easting > map.maxEasting || northing < map.minNorthing || northing > map.maxNorthing {
                    pixels[i] = Self.byte(surround.red * g)
                    pixels[i + 1] = Self.byte(surround.green * g)
                    pixels[i + 2] = Self.byte(surround.blue * g)
                    continue
                }
                let fx = Double(column) / Double(step)
                let gx = min(Int(fx), points - 2), tx = fx - Double(gx)
                let texture = Double(fine[lookRow + ((originX + column) % period + period) % period])
                var colour = (0.0, 0.0, 0.0)
                for channel in 0..<3 {
                    let a = broad[(gy * points + gx) * 3 + channel], b = broad[(gy * points + gx + 1) * 3 + channel]
                    let c = broad[((gy + 1) * points + gx) * 3 + channel], d = broad[((gy + 1) * points + gx + 1) * 3 + channel]
                    let value = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty + texture
                    switch channel {
                    case 0: colour.0 = value
                    case 1: colour.1 = value
                    default: colour.2 = value
                    }
                }
                pixels[i] = Self.byte(ground.red * colour.0 * g)
                pixels[i + 1] = Self.byte(ground.green * colour.1 * g)
                pixels[i + 2] = Self.byte(ground.blue * colour.2 * g)
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

    /// The same, but the lattice wraps round after `wrap` cells, so the noise repeats exactly every `wrap` units.
    static func wrappedNoise(_ x: Double, _ y: Double, wrap: Int, _ seed: UInt64) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func corner(_ dx: Int, _ dy: Int) -> Double {
            let cx = ((Int(x0) + dx) % wrap + wrap) % wrap, cy = ((Int(y0) + dy) % wrap + wrap) % wrap
            let h = hash(UInt64(bitPattern: Int64(cx)) &* 374761393 ^ UInt64(bitPattern: Int64(cy)) &* 668265263 ^ seed &* 2246822519)
            return Double(h % 10001) / 10000
        }
        let top = corner(0, 0) * (1 - sx) + corner(1, 0) * sx
        let bottom = corner(0, 1) * (1 - sx) + corner(1, 1) * sx
        return top * (1 - sy) + bottom * sy
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
