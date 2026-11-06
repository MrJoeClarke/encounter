//
//  MapStyle.swift
//  encounter
//

import Foundation

/// How a vector map looks: the paper it is drawn on and how each type of place is drawn on it. The first style, Dark, is the look
/// maps have always had; the others change the colours and weights of the same drawing. A style is plain data, so more can be
/// added, and the order in which things are drawn is the same in every style, so a forest is always under a river.
nonisolated struct MapStyle: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    /// What the map is drawn on.
    let background: StyleColor
    /// The colour of names on the map, and of the halo round them that keeps them readable over whatever is under.
    let ink: StyleColor
    let halo: StyleColor
    /// The colour of pins, and of a capital's.
    let pin: StyleColor
    let capitalPin: StyleColor
    /// Places of these types are drawn as given; any other type is drawn as in the Dark style.
    private let places: [String: Look]
    /// What shows at each zoom.
    var zoom = ZoomRules.standard
    /// The grain, mottling and ageing of the paper the map is drawn on, if it is drawn on paper rather than a flat colour.
    var paper: PaperTexture?
    /// The typeface names are set in, if not the system's serif.
    var lettering: Lettering?
    /// What lies outside the sheet the map is drawn on.
    var surround = StyleColor(red: 0.05, green: 0.05, blue: 0.06)
    /// The ruled border drawn just inside the edge of the sheet, if any.
    var frame: SheetFrame?
    /// How lines and outlines are drawn if they are to look drawn by hand; nil for the clean line of a plan.
    var hand: HandDrawn?
    /// The colour a chosen place is highlighted in.
    var accent = StyleColor(red: 1, green: 0.75, blue: 0.2)
    /// The drawn trees, peaks and shore lines of a map in this style, if it has them.
    var symbols: Symbols?
    /// Washes that pool a little darker at their edge, as watercolour does.
    var wash: Wash?
    /// The ink of a grid of squares over the sheet, as on a survey map.
    var gridInk: StyleColor?

    /// A typeface by its names: the regular face and the ones for italic, semibold and semibold italic.
    struct Lettering: Equatable, Sendable {
        var regular: String
        var italic: String
        var semibold: String
        var semiboldItalic: String

        static let baskerville = Lettering(regular: "Baskerville", italic: "Baskerville-Italic", semibold: "Baskerville-SemiBold", semiboldItalic: "Baskerville-SemiBoldItalic")
    }

    /// The look of a pen: how far a line wanders from the true line, over what distance, and how much the stroke thickens and thins
    /// (from 0 for an even stroke). The first two are in points on screen.
    struct HandDrawn: Equatable, Sendable {
        var amplitude: Double
        var wavelength: Double
        var weight: Double

        /// The types of place drawn in this way; buildings, rooms and the like stay crisp.
        static let types: Set<String> = ["Water", "Lake", "Region", "Wilderness", "Forest", "Mountains", "District", "Settlement", "River", "Road", "Street", "Wall"]
    }

    /// The inks of the symbols drawn over the land.
    struct Symbols: Equatable, Sendable {
        var tree: StyleColor
        var treeWash: StyleColor
        var peak: StyleColor
        /// The ink of lines along a shore, or nil for none.
        var shore: StyleColor?
        /// Trees in tidy rows, as on a survey, instead of scattered.
        var regular = false
        /// Mountains drawn as contour lines instead of peaks.
        var contours = false
        /// Soft dabs of colour instead of inked drawings.
        var soft = false
    }

    /// An edge where the colour of a wash gathers, as paint does: how wide the band is, in points, and how strong.
    struct Wash: Equatable, Sendable {
        var band: Double
        var strength: Double
    }

    /// A ruled border: an outer line and, if wanted, a finer one inside it, with a gap between, all in points on screen.
    struct SheetFrame: Equatable, Sendable {
        var ink: StyleColor
        var outer: Double
        var inner: Double
        var gap: Double
    }

    /// What a style says about one type of place: the parts that change from style to style.
    struct Look: Equatable, Sendable {
        var fill: StyleColor?
        var stroke: StyleColor
        var lineWidth: Double
        var isDashed = false
        var dash: [Double]?
    }

    /// The style for a type of place: the style's own look for it if it has one, in the same layer as ever.
    func style(forPlaceType type: String?) -> PlaceStyle {
        var base = PlaceStyle.style(forPlaceType: type)
        guard let type, let look = places[type] else { return base }
        base.fill = look.fill
        base.stroke = look.stroke
        base.lineWidth = look.lineWidth
        base.isDashed = look.isDashed
        base.dashPattern = look.dash
        return base
    }

    /// The id of the style that is used when none is chosen.
    static let defaultID = "dark"

    /// The built-in styles, in the order they are offered.
    static let all: [MapStyle] = [dark, parchment, survey, watercolour]

    /// The style with the id, or Dark if there isn't one (an empty id, or a style a newer version made).
    static func style(id: String) -> MapStyle { all.first { $0.id == id } ?? dark }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> StyleColor { StyleColor(red: r, green: g, blue: b, alpha: a) }

    // MARK: The styles

    /// The look maps have always had: a dark ground with bright lines.
    static let dark = MapStyle(
        id: "dark", title: String(localized: "Dark"), summary: String(localized: "A dark ground with bright lines."),
        background: color(0.13, 0.13, 0.14), ink: color(0.93, 0.93, 0.93), halo: color(0.1, 0.1, 0.11, 0.9),
        pin: color(0.9, 0.3, 0.25), capitalPin: color(0.98, 0.78, 0.2), places: [:],
        surround: color(0.04, 0.04, 0.05), frame: SheetFrame(ink: color(0.55, 0.55, 0.58), outer: 1.2, inner: 0, gap: 6)
    )

    /// An old map: cream paper, brown ink, muted washes.
    static let parchment = MapStyle(
        id: "parchment", title: String(localized: "Parchment"), summary: String(localized: "Cream paper, brown ink and muted washes, like an old fantasy map."),
        background: color(0.93, 0.87, 0.73), ink: color(0.3, 0.18, 0.08), halo: color(0.93, 0.87, 0.73, 0.9),
        pin: color(0.6, 0.25, 0.15), capitalPin: color(0.55, 0.08, 0.08),
        places: [
            "Water": Look(fill: color(0.55, 0.68, 0.72, 0.6), stroke: color(0.35, 0.45, 0.5), lineWidth: 1.5),
            "Lake": Look(fill: color(0.55, 0.68, 0.72, 0.8), stroke: color(0.35, 0.45, 0.5), lineWidth: 1.5),
            "Region": Look(fill: color(0.7, 0.55, 0.35, 0.12), stroke: color(0.55, 0.2, 0.12), lineWidth: 1.6, isDashed: true, dash: [9, 3, 1.5, 3]),
            "Wilderness": Look(fill: color(0.7, 0.62, 0.4, 0.3), stroke: color(0.5, 0.4, 0.25), lineWidth: 1),
            "Forest": Look(fill: color(0.45, 0.55, 0.3, 0.22), stroke: color(0.3, 0.4, 0.2), lineWidth: 1),
            "Mountains": Look(fill: color(0.62, 0.5, 0.38, 0.2), stroke: color(0.4, 0.3, 0.2), lineWidth: 1.2),
            "District": Look(fill: color(0.8, 0.65, 0.35, 0.15), stroke: color(0.55, 0.38, 0.15), lineWidth: 1.5, isDashed: true),
            "Settlement": Look(fill: color(0.8, 0.5, 0.25, 0.3), stroke: color(0.5, 0.3, 0.12), lineWidth: 2),
            "Building": Look(fill: color(0.6, 0.45, 0.33, 0.85), stroke: color(0.3, 0.2, 0.1), lineWidth: 1),
            "River": Look(fill: nil, stroke: color(0.35, 0.5, 0.6), lineWidth: 3),
            "Road": Look(fill: nil, stroke: color(0.4, 0.26, 0.12), lineWidth: 1.8),
            "Street": Look(fill: nil, stroke: color(0.5, 0.38, 0.25), lineWidth: 1.2),
            "Square": Look(fill: color(0.85, 0.75, 0.55, 0.5), stroke: color(0.5, 0.38, 0.2), lineWidth: 1.5),
            "Garden": Look(fill: color(0.5, 0.6, 0.35, 0.4), stroke: color(0.35, 0.45, 0.25), lineWidth: 1.5, isDashed: true),
            "Landmark": Look(fill: color(0.7, 0.45, 0.2, 0.9), stroke: color(0.35, 0.2, 0.08), lineWidth: 1.5),
            "Wall": Look(fill: nil, stroke: color(0.35, 0.25, 0.15), lineWidth: 3.5),
        ],
        paper: PaperTexture(), lettering: .baskerville,
        surround: color(0.2, 0.14, 0.09), frame: SheetFrame(ink: color(0.3, 0.18, 0.08), outer: 2.6, inner: 0.8, gap: 6),
        hand: HandDrawn(amplitude: 0.9, wavelength: 16, weight: 0.35),
        accent: color(0.72, 0.1, 0.08),
        symbols: Symbols(tree: color(0.25, 0.33, 0.14), treeWash: color(0.5, 0.6, 0.32, 0.45), peak: color(0.3, 0.2, 0.12), shore: color(0.35, 0.45, 0.5))
    )

    /// An ordnance survey: white paper, fine dark lines, pale fills, red roads.
    static let survey = MapStyle(
        id: "survey", title: String(localized: "Survey"), summary: String(localized: "Plain paper, thin dark lines and pale fills, like a survey map."),
        background: color(0.97, 0.97, 0.95), ink: color(0.15, 0.15, 0.15), halo: color(1, 1, 1, 0.9),
        pin: color(0.3, 0.3, 0.3), capitalPin: color(0.75, 0.2, 0.2),
        places: [
            "Water": Look(fill: color(0.7, 0.82, 0.92, 0.75), stroke: color(0.4, 0.6, 0.8), lineWidth: 1),
            "Lake": Look(fill: color(0.7, 0.82, 0.92, 0.9), stroke: color(0.4, 0.6, 0.8), lineWidth: 1),
            "Region": Look(fill: color(0.3, 0.3, 0.3, 0.04), stroke: color(0.5, 0.5, 0.5), lineWidth: 1, isDashed: true),
            "Wilderness": Look(fill: color(0.85, 0.85, 0.7, 0.4), stroke: color(0.6, 0.6, 0.45), lineWidth: 0.8),
            "Forest": Look(fill: color(0.78, 0.88, 0.72, 0.75), stroke: color(0.55, 0.7, 0.5), lineWidth: 0.8),
            "Mountains": Look(fill: color(0.86, 0.82, 0.76, 0.75), stroke: color(0.6, 0.55, 0.5), lineWidth: 0.8),
            "District": Look(fill: color(0.9, 0.85, 0.6, 0.25), stroke: color(0.6, 0.5, 0.2), lineWidth: 1, isDashed: true),
            "Settlement": Look(fill: color(0.9, 0.75, 0.6, 0.4), stroke: color(0.55, 0.35, 0.2), lineWidth: 1.2),
            "Building": Look(fill: color(0.78, 0.76, 0.73, 1), stroke: color(0.35, 0.35, 0.35), lineWidth: 0.6),
            "River": Look(fill: nil, stroke: color(0.35, 0.6, 0.85), lineWidth: 1.8),
            "Road": Look(fill: nil, stroke: color(0.75, 0.3, 0.25), lineWidth: 1.6),
            "Street": Look(fill: nil, stroke: color(0.3, 0.3, 0.3), lineWidth: 0.8),
            "Square": Look(fill: color(0.9, 0.88, 0.8, 0.8), stroke: color(0.45, 0.45, 0.45), lineWidth: 0.8),
            "Garden": Look(fill: color(0.8, 0.9, 0.75, 0.7), stroke: color(0.5, 0.65, 0.45), lineWidth: 0.8, isDashed: true),
            "Landmark": Look(fill: color(0.55, 0.55, 0.55, 1), stroke: color(0.2, 0.2, 0.2), lineWidth: 0.8),
            "Wall": Look(fill: nil, stroke: color(0.2, 0.2, 0.2), lineWidth: 2),
        ],
        paper: PaperTexture(grain: 0.012, mottle: 0.012, stain: 0, edge: 0, crumple: 0, fibre: 0.012),
        lettering: Lettering(regular: "Helvetica", italic: "Helvetica-Oblique", semibold: "Helvetica-Bold", semiboldItalic: "Helvetica-BoldOblique"),
        surround: color(0.8, 0.81, 0.83), frame: SheetFrame(ink: color(0.1, 0.1, 0.1), outer: 1.6, inner: 0.5, gap: 5),
        hand: HandDrawn(amplitude: 0, wavelength: 16, weight: 0),
        accent: color(0.86, 0.08, 0.08),
        symbols: Symbols(tree: color(0.22, 0.42, 0.22), treeWash: color(0.78, 0.88, 0.72, 0.5), peak: color(0.5, 0.36, 0.22), shore: nil, regular: true, contours: true),
        gridInk: color(0.4, 0.58, 0.85, 0.5)
    )

    /// Painted washes on white paper: soft colour, broad pale edges where ink would be, no hard black.
    static let watercolour = MapStyle(
        id: "watercolour", title: String(localized: "Watercolour"), summary: String(localized: "Soft washes of colour on white paper, with wide pale edges."),
        background: color(0.98, 0.97, 0.94), ink: color(0.35, 0.3, 0.3), halo: color(1, 1, 1, 0.85),
        pin: color(0.78, 0.38, 0.28), capitalPin: color(0.75, 0.35, 0.45),
        places: [
            "Water": Look(fill: color(0.55, 0.75, 0.88, 0.55), stroke: color(0.55, 0.75, 0.88, 0.6), lineWidth: 4),
            "Lake": Look(fill: color(0.5, 0.75, 0.85, 0.7), stroke: color(0.5, 0.75, 0.85, 0.7), lineWidth: 3),
            "Region": Look(fill: color(0.85, 0.7, 0.55, 0.1), stroke: color(0.62, 0.45, 0.68, 0.6), lineWidth: 3, isDashed: true, dash: [1.5, 6]),
            "Wilderness": Look(fill: color(0.85, 0.8, 0.55, 0.35), stroke: color(0.8, 0.75, 0.5, 0.4), lineWidth: 3),
            "Forest": Look(fill: color(0.55, 0.75, 0.55, 0.55), stroke: color(0.55, 0.75, 0.55, 0.45), lineWidth: 3),
            "Mountains": Look(fill: color(0.75, 0.68, 0.62, 0.6), stroke: color(0.65, 0.55, 0.5, 0.5), lineWidth: 3),
            "District": Look(fill: color(0.95, 0.8, 0.5, 0.2), stroke: color(0.9, 0.7, 0.4, 0.5), lineWidth: 3),
            "Settlement": Look(fill: color(0.95, 0.7, 0.45, 0.4), stroke: color(0.9, 0.6, 0.35, 0.55), lineWidth: 3),
            "Building": Look(fill: color(0.88, 0.68, 0.58, 0.85), stroke: color(0.7, 0.5, 0.45, 0.7), lineWidth: 1),
            "River": Look(fill: nil, stroke: color(0.45, 0.7, 0.88, 0.9), lineWidth: 3.5),
            "Road": Look(fill: nil, stroke: color(0.78, 0.62, 0.48, 0.85), lineWidth: 2),
            "Street": Look(fill: nil, stroke: color(0.72, 0.62, 0.52, 0.75), lineWidth: 1.2),
            "Square": Look(fill: color(0.92, 0.85, 0.7, 0.6), stroke: color(0.8, 0.7, 0.55, 0.6), lineWidth: 2),
            "Garden": Look(fill: color(0.65, 0.82, 0.6, 0.5), stroke: color(0.6, 0.78, 0.55, 0.5), lineWidth: 2),
            "Landmark": Look(fill: color(0.9, 0.65, 0.4, 0.9), stroke: color(0.7, 0.45, 0.3, 0.8), lineWidth: 1.5),
            "Wall": Look(fill: nil, stroke: color(0.55, 0.5, 0.5, 0.85), lineWidth: 3),
        ],
        paper: PaperTexture(grain: 0.045, mottle: 0.03, stain: 0.02, edge: 0.05, edgeReach: 0.05, crumple: 0.02, fibre: 0.05),
        lettering: Lettering(regular: "Optima-Regular", italic: "Optima-Italic", semibold: "Optima-Bold", semiboldItalic: "Optima-BoldItalic"),
        surround: color(0.9, 0.89, 0.86), frame: SheetFrame(ink: color(0.8, 0.62, 0.5, 0.7), outer: 3, inner: 0, gap: 6),
        hand: HandDrawn(amplitude: 1.3, wavelength: 24, weight: 0.5),
        accent: color(0.82, 0.22, 0.4),
        symbols: Symbols(tree: color(0.3, 0.5, 0.3), treeWash: color(0.45, 0.7, 0.45, 0.55), peak: color(0.5, 0.4, 0.35), shore: color(0.45, 0.65, 0.85), soft: true),
        wash: Wash(band: 7, strength: 0.55)
    )
}
