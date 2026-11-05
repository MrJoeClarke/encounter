//
//  SheetGrid.swift
//  encounter
//

import MapKit

/// A grid of squares over the sheet of a vector map, as on a survey map, whose lines are a round number of metres apart (1, 2 or 5
/// times a power of ten) and far enough apart on screen to read, so there are fewer of them as you zoom out.
final class SheetGridOverlay: NSObject, MKOverlay {
    let sheet: MKMapRect
    let ink: StyleColor

    init(sheet: MKMapRect, ink: StyleColor) {
        self.sheet = sheet
        self.ink = ink
    }

    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: sheet.midX, y: sheet.midY).coordinate }
    var boundingMapRect: MKMapRect { sheet }
}

final class SheetGridRenderer: MKOverlayRenderer {
    private let grid: SheetGridOverlay

    init(grid: SheetGridOverlay) {
        self.grid = grid
        super.init(overlay: grid)
    }

    /// MapKit's points in the middle of the world, which is where the plane's easting and northing are nothing.
    private static let middle = 134_217_728.0

    /// The gap between lines, in metres, for a screen point that is `metresPerPoint` metres: the longest 1, 2 or 5 times a power of ten
    /// that is at least `minimum` points.
    static func spacing(metresPerPoint: Double, minimum: Double = 70) -> Double {
        let wanted = metresPerPoint * minimum
        let power = pow(10, floor(log10(max(wanted, 1e-9))))
        return [1.0, 2.0, 5.0, 10.0].map { $0 * power }.first { $0 >= wanted } ?? power * 10
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let metresPerMapPoint = WebMercator.worldSize / 268_435_456
        let metresPerPoint = metresPerMapPoint / Double(zoomScale)
        let gap = Self.spacing(metresPerPoint: metresPerPoint) / metresPerMapPoint   // in MapKit's points
        let area = mapRect.intersection(grid.sheet)
        guard !area.isNull, gap > 0 else { return }
        context.setStrokeColor(CGColor(red: grid.ink.red, green: grid.ink.green, blue: grid.ink.blue, alpha: grid.ink.alpha))
        context.setLineWidth(0.6 / Double(zoomScale))
        // Lines at whole numbers of gaps from where the plane's easting and northing are nothing.
        var x = (((area.minX - Self.middle) / gap).rounded(.up)) * gap + Self.middle
        context.beginPath()
        while x <= area.maxX {
            context.move(to: point(for: MKMapPoint(x: x, y: area.minY)))
            context.addLine(to: point(for: MKMapPoint(x: x, y: area.maxY)))
            x += gap
        }
        var y = (((area.minY - Self.middle) / gap).rounded(.up)) * gap + Self.middle
        while y <= area.maxY {
            context.move(to: point(for: MKMapPoint(x: area.minX, y: y)))
            context.addLine(to: point(for: MKMapPoint(x: area.maxX, y: y)))
            y += gap
        }
        context.strokePath()
    }
}
