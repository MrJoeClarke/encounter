//
//  MapGlyphs.swift
//  encounter
//

import SwiftUI

/// The pictures the map is annotated with: pins, and names drawn with a halo. They are drawn in the colours of the map's style, and
/// kept, since the same few are wanted over and over.
@MainActor
enum MapGlyphs {
    private static var cache: [String: PlatformImage] = [:]

    private static func render<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> PlatformImage? {
        if let kept = cache[key] { return kept }
        let renderer = ImageRenderer(content: content())
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        let size = CGSize(width: Double(image.width) / 3, height: Double(image.height) / 3)
        #if os(macOS)
        let made = PlatformImage(cgImage: image, size: size)
        #else
        let made = PlatformImage(cgImage: image, scale: 3, orientation: .up)
        #endif
        cache[key] = made
        return made
    }

    private static func swiftUI(_ c: StyleColor) -> Color { Color(red: c.red, green: c.green, blue: c.blue).opacity(c.alpha) }

    /// A round pin with the kind's icon in it. A capital has a ring round it.
    static func pin(_ kind: PlacePinKind, style: MapStyle) -> PlatformImage? {
        let tint = kind == .capital ? style.capitalPin : style.pin
        let size = kind.size
        return render("pin|\(kind.rawValue)|\(style.id)") {
            ZStack {
                Circle().fill(swiftUI(tint))
                Circle().strokeBorder(swiftUI(style.halo.with(alpha: 1)), lineWidth: kind == .capital ? 2.5 : 1.5)
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .padding(2)
        }
    }

    /// A name, in the style's ink with a halo, sized and shaped by what is named. A name along a line is turned `degrees`
    /// anticlockwise inside a picture just big enough for it, so the picture's middle is the middle of the name wherever the
    /// map turns it.
    static func label(_ text: String, type: String, style: MapStyle, degrees: Double = 0) -> PlatformImage? {
        let flat = render("label|\(text)|\(type)|\(style.id)") { labelText(text, type: type, style: style) }
        let turn = degrees.rounded()
        guard turn != 0, let flat else { return flat }
        let radians = turn * .pi / 180
        let width = abs(flat.size.width * cos(radians)) + abs(flat.size.height * sin(radians))
        let height = abs(flat.size.width * sin(radians)) + abs(flat.size.height * cos(radians))
        return render("label|\(text)|\(type)|\(style.id)|\(Int(turn))") {
            labelText(text, type: type, style: style)
                .rotationEffect(.degrees(-turn))
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private static func labelText(_ text: String, type: String, style: MapStyle) -> some View {
        let look = Self.look(of: type)
        let ink = swiftUI(style.ink), halo = swiftUI(style.halo)
        Text(look.uppercased ? text.uppercased() : text)
            .font(.system(size: look.size, weight: look.weight, design: look.serif ? .serif : .default))
            .italic(look.italic)
            .tracking(look.tracking)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: halo, radius: 0, x: 1, y: 0)
            .shadow(color: halo, radius: 0, x: -1, y: 0)
            .shadow(color: halo, radius: 0, x: 0, y: 1)
            .shadow(color: halo, radius: 0, x: 0, y: -1)
            .shadow(color: halo, radius: 2)
            .padding(3)
    }

    /// A name on the map as a small label under a pin.
    static func pinLabel(_ text: String, kind: PlacePinKind, style: MapStyle) -> PlatformImage? {
        label(text, type: kind == .capital ? "PinCapital" : "Pin", style: style)
    }

    private struct Look {
        var size: Double
        var weight: Font.Weight = .regular
        var italic = false
        var uppercased = false
        var tracking = 0.0
        var serif = true
    }

    private static func look(of type: String) -> Look {
        switch type {
        case "Region": Look(size: 15, weight: .semibold, uppercased: true, tracking: 3)
        case "Water": Look(size: 14, italic: true, tracking: 2)
        case "Lake": Look(size: 12, italic: true, tracking: 1)
        case "Mountains": Look(size: 12, weight: .medium, italic: true, tracking: 1)
        case "Forest", "Wilderness": Look(size: 12, italic: true, tracking: 1)
        case "District": Look(size: 12, weight: .semibold, uppercased: true, tracking: 1.5)
        case "River": Look(size: 11, italic: true)
        case "Road": Look(size: 10, weight: .medium)
        case "Street": Look(size: 9)
        case "Wall": Look(size: 9, italic: true)
        case "Garden", "Square": Look(size: 10, italic: true)
        case "PinCapital": Look(size: 12, weight: .bold, serif: false)
        case "Pin": Look(size: 10, weight: .medium, serif: false)
        default: Look(size: 10, serif: false)
        }
    }
}

private let sampleKinds: [PlacePinKind] = [.capital, .city, .town, .village, .cathedral, .castle, .university, .library, .guildhall, .arena, .infirmary, .wizardsTower, .prison, .landmark, .place]

private struct SampleName: Identifiable {
    let text: String
    let type: String
    var id: String { text }
}

private let sampleNames: [SampleName] = [
    SampleName(text: "Carrowmere", type: "Region"), SampleName(text: "The Grey Sea", type: "Water"), SampleName(text: "Lake Hale", type: "Lake"),
    SampleName(text: "Thornwood", type: "Forest"), SampleName(text: "Ironspine", type: "Mountains"), SampleName(text: "Old Quarter", type: "District"),
    SampleName(text: "River Dunn", type: "River"), SampleName(text: "Marsh–Wick Road", type: "Road"), SampleName(text: "Mill Street", type: "Street"),
    SampleName(text: "Aldford", type: "Pin"), SampleName(text: "Roschester", type: "PinCapital"),
]

private struct GlyphSamples: View {
    let style: MapStyle

    var body: some View {
        let ground = Color(red: style.background.red, green: style.background.green, blue: style.background.blue)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(sampleKinds, id: \.self) { kind in
                    if let image = MapGlyphs.pin(kind, style: style) { Image(platformImage: image) }
                }
            }
            HStack(spacing: 14) {
                ForEach(sampleNames) { sample in
                    if let image = MapGlyphs.label(sample.text, type: sample.type, style: style) { Image(platformImage: image) }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ground)
    }
}

#Preview("Pins and names") {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(MapStyle.all) { style in GlyphSamples(style: style) }
    }
    .frame(width: 1250)
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
