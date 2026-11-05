//
//  MapTileSource.swift
//  encounter
//

import Foundation
import CoreGraphics
import ImageIO
import MapKit
import UniformTypeIdentifiers

/// Cuts map tiles out of a calibrated map image, for showing it in MapKit. A tile covers some square of the
/// world's plane, and the image (turned and scaled by its calibration) is drawn into it. Reduced copies of a big
/// image are made as they're needed, so zoomed-out tiles don't decode every pixel.
nonisolated final class MapTileSource: @unchecked Sendable {
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let calibration: MapCalibration

    private let lock = NSLock()
    /// Reduced copies by how many times smaller they are than the image: 1, 2, 4 and so on.
    private var levels: [Int: CGImage] = [:]
    private var emptyTile: Data?

    static let background = CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)

    /// What a map with no picture is drawn on, and what lies outside a picture.
    var background = MapTileSource.background

    /// The paper a map with no picture is drawn on, if it has any texture; otherwise it is the plain background.
    var paper: PaperTexture?

    /// What lies outside the sheet of a map with no picture, so the map is a bounded sheet. Without it the map runs on all round.
    var surround: CGColor?

    init(imageData: Data, pixelWidth: Int, pixelHeight: Int, calibration: MapCalibration) {
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.calibration = calibration
    }

    /// The plane area the image covers, as the smallest box around its four corners.
    var bounds: (minEasting: Double, minNorthing: Double, maxEasting: Double, maxNorthing: Double) {
        let corners = [(0.0, 0.0), (Double(pixelWidth), 0), (0, Double(pixelHeight)), (Double(pixelWidth), Double(pixelHeight))]
            .map { calibration.gridPoint(atX: $0.0, y: $0.1) }
        return (
            corners.map(\.easting).min() ?? 0, corners.map(\.northing).min() ?? 0,
            corners.map(\.easting).max() ?? 0, corners.map(\.northing).max() ?? 0
        )
    }

    /// The most detailed zoom worth cutting tiles for, where a tile pixel is about an image pixel.
    var maximumZoom: Int {
        WebMercator.zoom(forMetresPerPixel: calibration.metresPerPixel)
    }

    /// How much deeper than the image's own resolution tiles are cut, which magnifies the image a little so the map can
    /// be zoomed in on without it running out. Past this MapKit stops asking for tiles and shows the world beneath.
    static let overzoom = 3

    /// The deepest zoom tiles are made for, and so the deepest the map is zoomed to.
    var maximumDisplayZoom: Int { min(maximumZoom + Self.overzoom, 21) }

    /// The PNG for one tile. Tiles the image doesn't touch are the plain background.
    func tile(zoom: Int, x: Int, y: Int) -> Data? {
        // A map with no picture is the plain background everywhere.
        if imageData.isEmpty { return sheetTile(zoom: zoom, x: x, y: y) }
        let area = WebMercator.bounds(zoom: zoom, x: x, y: y)
        let covered = bounds
        guard area.maxEasting > covered.minEasting, area.minEasting < covered.maxEasting,
              area.maxNorthing > covered.minNorthing, area.minNorthing < covered.maxNorthing
        else { return emptyTileData() }

        // Use the smallest reduced copy that still has a pixel for each pixel of the tile.
        let tileMetresPerPixel = WebMercator.tileMetres(zoom: zoom) / WebMercator.tileSize
        let reduction = Self.reduction(forTilePixelMetres: tileMetresPerPixel, imagePixelMetres: calibration.metresPerPixel)
        guard let image = level(reduction: reduction) else { return nil }
        return render(image, reduction: reduction, area: area)
    }

    // MARK: Drawing

    private func rgb(_ color: CGColor) -> (red: Double, green: Double, blue: Double) {
        let c = color.components ?? []
        return c.count >= 3 ? (Double(c[0]), Double(c[1]), Double(c[2])) : (Double(c.first ?? 0), Double(c.first ?? 0), Double(c.first ?? 0))
    }

    /// A tile of a map with no picture: the paper or plain ground inside the sheet, and the surround outside it.
    private func sheetTile(zoom: Int, x: Int, y: Int) -> Data? {
        let area = WebMercator.bounds(zoom: zoom, x: x, y: y)
        let sheet = bounds
        let size = Int(WebMercator.tileSize)
        if let paper {
            return paper.tile(ground: rgb(background), surround: surround.map(rgb), area: area, map: sheet, size: size).flatMap(Self.png)
        }
        guard let surround else { return emptyTileData() }
        let inside = area.minEasting >= sheet.minEasting && area.maxEasting <= sheet.maxEasting && area.minNorthing >= sheet.minNorthing && area.maxNorthing <= sheet.maxNorthing
        if inside { return emptyTileData() }
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(surround)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let k = Double(size) / (area.maxEasting - area.minEasting)
        context.setFillColor(background)
        context.fill(CGRect(x: (sheet.minEasting - area.minEasting) * k, y: (sheet.minNorthing - area.minNorthing) * k,
                            width: (sheet.maxEasting - sheet.minEasting) * k, height: (sheet.maxNorthing - sheet.minNorthing) * k))
        return context.makeImage().flatMap(Self.png)
    }

    /// A power of two: how many image pixels one pixel of the copy stands for.
    static func reduction(forTilePixelMetres tile: Double, imagePixelMetres image: Double) -> Int {
        guard image > 0, tile > image else { return 1 }
        var reduction = 1
        while Double(reduction * 2) * image <= tile { reduction *= 2 }
        return reduction
    }

    private func render(_ image: CGImage, reduction: Int, area: (minEasting: Double, minNorthing: Double, maxEasting: Double, maxNorthing: Double)) -> Data? {
        let size = Int(WebMercator.tileSize)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // From the copy's pixels (x across, y up) to the tile's (x across, y up). The image's own y runs down
        // and its calibration's north runs up, so the copy's height comes into the offset.
        let k = Double(size) / (area.maxEasting - area.minEasting)
        let f = Double(reduction)
        let s = calibration.metresPerPixel
        let cosT = cos(calibration.rotation), sinT = sin(calibration.rotation)
        let h = Double(image.height)
        context.concatenate(CGAffineTransform(
            a: s * f * cosT * k, b: s * f * sinT * k,
            c: -s * f * sinT * k, d: s * f * cosT * k,
            tx: (calibration.originEasting + s * f * h * sinT - area.minEasting) * k,
            ty: (calibration.originNorthing - s * f * h * cosT - area.minNorthing) * k
        ))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage().flatMap(Self.png)
    }

    private func emptyTileData() -> Data? {
        lock.lock(); defer { lock.unlock() }
        if let emptyTile { return emptyTile }
        let size = Int(WebMercator.tileSize)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        emptyTile = context.makeImage().flatMap(Self.png)
        return emptyTile
    }

    private func level(reduction: Int) -> CGImage? {
        lock.lock()
        if let cached = levels[reduction] { lock.unlock(); return cached }
        lock.unlock()
        // Decoding can take a while for a big image, so it happens outside the lock. Two tiles asking at the
        // same time may both decode it, and one copy is kept.
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let longest = max(pixelWidth, pixelHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest / reduction, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let existing = levels[reduction] { return existing }
        levels[reduction] = image
        return image
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// A MapKit overlay that draws a calibrated map in place of the base map.
final class MapTileOverlay: MKTileOverlay {
    let source: MapTileSource

    init(source: MapTileSource) {
        self.source = source
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: WebMercator.tileSize, height: WebMercator.tileSize)
        // Every tile is opaque, so MapKit needn't draw the world underneath.
        canReplaceMapContent = true
        minimumZ = 0
        maximumZ = source.maximumDisplayZoom
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let source = source
        DispatchQueue.global(qos: .userInitiated).async {
            result(source.tile(zoom: path.z, x: path.x, y: path.y), nil)
        }
    }
}
