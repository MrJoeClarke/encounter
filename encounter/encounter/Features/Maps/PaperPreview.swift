//
//  PaperPreview.swift
//  encounter
//

import SwiftUI

/// The paper of a style over the whole of a map, and over a closer part of it.
private struct PaperSample: View {
    let style: MapStyle

    private func image(of area: PaperTexture.Area, in map: PaperTexture.Area) -> Image {
        let ground = (red: style.background.red, green: style.background.green, blue: style.background.blue)
        guard let paper = style.paper, let made = paper.tile(ground: ground, area: area, map: map, size: 360) else { return Image(systemName: "xmark") }
        return Image(decorative: made, scale: 1)
    }

    var body: some View {
        let map: PaperTexture.Area = (0, 0, 10_000, 10_000)
        HStack(spacing: 8) {
            image(of: map, in: map)
            // A twelfth of the map, in from the corner, which shows the grain.
            image(of: (500, 500, 1_330, 1_330), in: map)
        }
        .padding(8)
    }
}

#Preview("Parchment paper") {
    PaperSample(style: .parchment)
}
