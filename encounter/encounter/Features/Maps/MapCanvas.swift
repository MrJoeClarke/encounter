//
//  MapCanvas.swift
//  encounter
//

import SwiftUI

/// A numbered mark drawn on the map at an image position.
struct MapMarker: Identifiable {
    let id: Int
    let pixelX: Double
    let pixelY: Double
    let label: String
}

/// A map image that can be zoomed and scrolled. Scrolling and zooming use the system's own gestures, and the
/// buttons zoom in steps or fit the whole map. Clicks and taps report the position in image pixels.
struct MapCanvas: View {
    let map: WorldMap
    var markers: [MapMarker] = []
    /// Called with the image position that was clicked or tapped, if set.
    var onTap: ((_ pixelX: Double, _ pixelY: Double) -> Void)?

    /// How far in the map is zoomed, where 1 fits the whole map in the view.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat?
    /// The map as shown. A huge map is decoded at a smaller size so it doesn't fill memory, while positions
    /// on it still count pixels of the full image.
    @State private var shownImage: CGImage?

    private let zoomRange: ClosedRange<CGFloat> = 0.25...24

    var body: some View {
        GeometryReader { viewport in
            let fit = fittedSize(in: viewport.size)
            let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    if let shownImage {
                        Image(decorative: shownImage, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                    }
                    ForEach(markers) { marker in
                        MarkerView(label: marker.label)
                            .position(
                                x: marker.pixelX / Double(max(map.pixelWidth, 1)) * size.width,
                                y: marker.pixelY / Double(max(map.pixelHeight, 1)) * size.height
                            )
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    onTap?(
                        Double(location.x / size.width) * Double(map.pixelWidth),
                        Double(location.y / size.height) * Double(map.pixelHeight)
                    )
                }
                // The map is centred when it is smaller than the view.
                .frame(minWidth: viewport.size.width, minHeight: viewport.size.height)
            }
            .defaultScrollAnchor(.center)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomAtGestureStart ?? zoom
                        zoomAtGestureStart = start
                        zoom = (start * value.magnification).clamped(to: zoomRange)
                    }
                    .onEnded { _ in zoomAtGestureStart = nil }
            )
            .overlay(alignment: .topTrailing) { zoomControls }
        }
        .background(.quaternary.opacity(0.4))
        .task(id: map.id) {
            guard let data = map.imageData else { return }
            shownImage = await ImageProcessing.downsampled(data, maxPixelSize: Self.shownDimension)
        }
    }

    /// The longest side, in pixels, a map is decoded at for showing.
    private static let shownDimension = 8192

    /// The largest size that fits the whole image inside the view.
    private func fittedSize(in available: CGSize) -> CGSize {
        guard map.pixelWidth > 0, map.pixelHeight > 0, available.width > 0, available.height > 0 else {
            return CGSize(width: max(available.width, 1), height: max(available.height, 1))
        }
        let scale = min(available.width / CGFloat(map.pixelWidth), available.height / CGFloat(map.pixelHeight))
        return CGSize(width: CGFloat(map.pixelWidth) * scale, height: CGFloat(map.pixelHeight) * scale)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom = (zoom / 1.5).clamped(to: zoomRange) }
            Button("Fit Map", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { zoom = 1 }
            Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom = (zoom * 1.5).clamped(to: zoomRange) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
    }
}

private struct MarkerView: View {
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .background(Circle().fill(Color.accentColor.opacity(0.85)))
                .frame(width: 22, height: 22)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .shadow(radius: 2)
        .allowsHitTesting(false)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
