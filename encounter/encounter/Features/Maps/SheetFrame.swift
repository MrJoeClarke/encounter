//
//  SheetFrame.swift
//  encounter
//

import MapKit

/// The ruled border drawn just inside the edge of the sheet a vector map is on. It is a fixed number of points from the edge whatever
/// the zoom, so it reads as the border of the page and not as a line on the map.
final class SheetFrameOverlay: NSObject, MKOverlay {
    let sheet: MKMapRect
    let frame: MapStyle.SheetFrame

    init(sheet: MKMapRect, frame: MapStyle.SheetFrame) {
        self.sheet = sheet
        self.frame = frame
    }

    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: sheet.midX, y: sheet.midY).coordinate }
    var boundingMapRect: MKMapRect { sheet }
}

final class SheetFrameRenderer: MKOverlayRenderer {
    private let frame: SheetFrameOverlay

    init(frame: SheetFrameOverlay) {
        self.frame = frame
        super.init(overlay: frame)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let look = frame.frame
        let point = 1 / Double(zoomScale)
        let sheet = rect(for: frame.sheet)
        context.setStrokeColor(CGColor(red: look.ink.red, green: look.ink.green, blue: look.ink.blue, alpha: look.ink.alpha))
        context.setLineJoin(.miter)
        func line(_ width: Double, inset: Double) {
            guard width > 0 else { return }
            context.setLineWidth(width * point)
            context.stroke(sheet.insetBy(dx: inset * point, dy: inset * point))
        }
        line(look.outer, inset: look.gap + look.outer / 2)
        line(look.inner, inset: look.gap + look.outer + look.outer * 1.5 + look.inner / 2)
    }
}
