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

/// A place drawn on the map at its position.
struct PlacePin: Identifiable {
    let page: Page
    let pixelX: Double
    let pixelY: Double
    var id: UUID { page.id }
}

/// A map image that can be zoomed and scrolled, with the places that are on it. Scrolling and zooming use the
/// system's own gestures, and the buttons zoom in steps or fit the whole map. Positions are in image pixels.
struct MapCanvas: View {
    let map: WorldMap
    var markers: [MapMarker] = []
    var pins: [PlacePin] = []
    /// Whether places can be put on the map (right-click, or press and hold).
    var canPlace = false
    /// Called with the image position that was clicked or tapped, if set. Used to mark calibration points.
    var onTap: ((_ pixelX: Double, _ pixelY: Double) -> Void)?
    /// Called with the image position the creator asked to put a place at.
    var onPlace: ((_ pixelX: Double, _ pixelY: Double) -> Void)?
    /// Called with a place and the image position it was dragged to.
    var onMove: ((_ page: Page, _ pixelX: Double, _ pixelY: Double) -> Void)?

    /// How far in the map is zoomed, where 1 fits the whole map in the view.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat?
    /// The map as shown. A huge map is decoded at a smaller size so it doesn't fill memory, while positions
    /// on it still count pixels of the full image.
    @State private var shownImage: CGImage?
    @State private var showsGrid = true
    /// The last place the pointer was over the map, which is where a right-click puts a place.
    @State private var pointer: CGPoint?

    private let zoomRange: ClosedRange<CGFloat> = 0.25...24

    var body: some View {
        GeometryReader { viewport in
            let fit = fittedSize(in: viewport.size)
            let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
            ScrollView([.horizontal, .vertical]) {
                content(size: size)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        let (x, y) = pixel(at: location, in: size)
                        onTap?(x, y)
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        if case .active(let location) = phase { pointer = location }
                    }
                    #if os(macOS)
                    .contextMenu {
                        if canPlace {
                            Button("Add Place Here…", systemImage: "mappin.and.ellipse") {
                                let (x, y) = pixel(at: pointer ?? CGPoint(x: size.width / 2, y: size.height / 2), in: size)
                                onPlace?(x, y)
                            }
                        }
                    }
                    #else
                    .gesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onEnded { value in
                                guard canPlace, case .second(true, let drag?) = value else { return }
                                let (x, y) = pixel(at: drag.location, in: size)
                                onPlace?(x, y)
                            }
                    )
                    #endif
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
            .overlay(alignment: .topTrailing) { controls }
        }
        .background(.quaternary.opacity(0.4))
        .task(id: map.id) {
            guard let data = map.imageData else { return }
            shownImage = await ImageProcessing.downsampled(data, maxPixelSize: Self.shownDimension)
        }
    }

    /// The longest side, in pixels, a map is decoded at for showing.
    private static let shownDimension = 8192

    private func content(size: CGSize) -> some View {
        ZStack {
            if let shownImage {
                Image(decorative: shownImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
            if showsGrid, map.kind == .scene, map.gridColumns > 0, map.gridRows > 0 {
                gridLines(columns: map.gridColumns, rows: map.gridRows)
            }
            ForEach(pins) { pin in
                PlacePinView(pin: pin, mapSize: size, map: map, onMove: onMove)
                    .position(
                        x: pin.pixelX / Double(max(map.pixelWidth, 1)) * size.width,
                        y: pin.pixelY / Double(max(map.pixelHeight, 1)) * size.height
                    )
            }
            ForEach(markers) { marker in
                MarkerView(label: marker.label)
                    .position(
                        x: marker.pixelX / Double(max(map.pixelWidth, 1)) * size.width,
                        y: marker.pixelY / Double(max(map.pixelHeight, 1)) * size.height
                    )
            }
        }
    }

    private func gridLines(columns: Int, rows: Int) -> some View {
        Canvas { context, size in
            var path = Path()
            for column in 0...columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
            context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.25)
        }
        .allowsHitTesting(false)
    }

    /// Where a position on the shown map is on the full image.
    private func pixel(at location: CGPoint, in size: CGSize) -> (Double, Double) {
        (
            Double(location.x / max(size.width, 1)) * Double(map.pixelWidth),
            Double(location.y / max(size.height, 1)) * Double(map.pixelHeight)
        )
    }

    /// The largest size that fits the whole image inside the view.
    private func fittedSize(in available: CGSize) -> CGSize {
        guard map.pixelWidth > 0, map.pixelHeight > 0, available.width > 0, available.height > 0 else {
            return CGSize(width: max(available.width, 1), height: max(available.height, 1))
        }
        let scale = min(available.width / CGFloat(map.pixelWidth), available.height / CGFloat(map.pixelHeight))
        return CGSize(width: CGFloat(map.pixelWidth) * scale, height: CGFloat(map.pixelHeight) * scale)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            if map.kind == .scene, map.gridColumns > 0 {
                Button("Grid", systemImage: showsGrid ? "grid" : "grid.circle") { showsGrid.toggle() }
            }
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

/// A place on the map: its icon and name. Tapping shows what can be done with it, and dragging moves it.
private struct PlacePinView: View {
    let pin: PlacePin
    let mapSize: CGSize
    let map: WorldMap
    var onMove: ((_ page: Page, _ pixelX: Double, _ pixelY: Double) -> Void)?

    @Environment(WorldNavigation.self) private var navigation
    @State private var isShowingDetails = false
    @State private var drag: CGSize = .zero

    var body: some View {
        // Only the icon takes up room, so its centre is exactly on the position. The name hangs below it.
        Image(systemName: pin.page.kind.systemImage)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.red.opacity(0.9)))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .overlay(alignment: .top) {
                Text(pin.page.title.isEmpty ? String(localized: "Untitled") : pin.page.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 4)
                    .background(.thinMaterial, in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: 28)
            }
            .shadow(radius: 2)
            .offset(drag)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    drag = .zero
                    let x = (pin.pixelX / Double(max(map.pixelWidth, 1)) * mapSize.width + value.translation.width) / max(mapSize.width, 1)
                    let y = (pin.pixelY / Double(max(map.pixelHeight, 1)) * mapSize.height + value.translation.height) / max(mapSize.height, 1)
                    onMove?(pin.page, x * Double(map.pixelWidth), y * Double(map.pixelHeight))
                }
        )
        .onTapGesture { isShowingDetails = true }
        .popover(isPresented: $isShowingDetails) { details }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.page.title)
        .accessibilityAddTraits(.isButton)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pin.page.title.isEmpty ? String(localized: "Untitled") : pin.page.title)
                .font(.headline)
            if !pin.page.summary.isEmpty {
                Text(pin.page.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Place", systemImage: "arrow.up.right.square") {
                isShowingDetails = false
                navigation.open(pin.page)
            }
            ForEach(pin.page.maps ?? []) { other in
                if other !== map {
                    Button("Open Map “\(other.name.isEmpty ? String(localized: "Untitled Map") : other.name)”", systemImage: "map") {
                        isShowingDetails = false
                        navigation.openMap(other)
                    }
                }
            }
            Button("Remove From Maps", systemImage: "mappin.slash", role: .destructive) {
                isShowingDetails = false
                pin.page.setGeometry(nil)
            }
        }
        .buttonStyle(.plain)
        .padding()
        .frame(minWidth: 220, alignment: .leading)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
