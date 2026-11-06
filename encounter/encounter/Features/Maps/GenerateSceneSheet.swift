//
//  GenerateSceneSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Chooses what a scene is like and shows the result before it is made. Making it adds a scene map of the place, on a grid of
/// five-foot squares, and a place for each room, corridor, door and staircase on it.
struct GenerateSceneSheet: View {
    let place: Page
    let onDone: (WorldMap?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var options: SceneOptions
    @State private var preview: GeneratedScene?
    @State private var isPreviewing = false
    @State private var making: (made: Int, total: Int)?
    @State private var isMaking = false
    @State private var generation: Task<Void, Never>?

    init(place: Page, onDone: @escaping (WorldMap?) -> Void) {
        self.place = place
        self.onDone = onDone
        var fresh = SceneOptions()
        fresh.seed = UInt64.random(in: 1...999_999)
        // A scene of a building is most likely the inside of it.
        fresh.kind = SceneGenerator.defaultKind(forPlaceType: place.attributeText("core.placeType"))
        _options = State(initialValue: fresh)
    }

    /// How big the scene is and the outline it fills: for a building with an outline, the outline decides both.
    private var plan: (squares: Int, outline: [GridPoint]?) { World.scenePlan(for: place, options: options) }

    private var amountTitle: LocalizedStringKey {
        switch options.kind {
        case .marketSquare: "Stalls"
        case .forestClearing: "Trees"
        default: "Rooms"
        }
    }

    private var existing: WorldMap? {
        (place.world?.maps ?? []).first { $0.place === place && $0.kind == .scene && $0.isVector && $0.generatorData != nil && !$0.isDeleted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScenePreview(scene: preview)
                        .frame(height: 320)
                        .opacity(isPreviewing && preview != nil ? 0.4 : 1)
                        .overlay {
                            if isMaking {
                                VStack(spacing: 8) {
                                    if let making, making.total > 0 {
                                        ProgressView(value: Double(making.made), total: Double(making.total))
                                            .frame(width: 180)
                                        Text("Making places: \(making.made) of \(making.total)")
                                    } else {
                                        ProgressView()
                                        Text("Laying out the scene…")
                                    }
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            } else if isPreviewing {
                                ProgressView().controlSize(.large)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    if let preview {
                        Text("^[\(preview.features(of: "Room").count + preview.features(of: "Cave").count) room](inflect: true), ^[\(preview.features(of: "Corridor").count) corridor](inflect: true), ^[\(preview.features(of: "Door").count) door](inflect: true), \(preview.squares) by \(preview.squares) squares")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Kind", selection: $options.kind) {
                        ForEach(SceneKind.allCases) { Text($0.title).tag($0) }
                    }
                    if plan.outline != nil {
                        LabeledContent("Size") { Text("\(plan.squares) squares, from the outline").foregroundStyle(.secondary) }
                    } else {
                        Stepper("Size: \(options.squares) squares", value: $options.squares, in: 10...100, step: 5)
                    }
                    // Only a market square has inns and shops to name.
                    if options.kind == .marketSquare { NamingStylePicker(styleID: $options.namingStyle) }
                    LabeledContent("Seed") {
                        HStack {
                            TextField("Seed", value: $options.seed, format: .number.grouping(.never))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Button("New Seed", systemImage: "dice") { options.seed = UInt64.random(in: 1...999_999) }
                                .labelStyle(.iconOnly)
                        }
                    }
                } header: {
                    Text("Scene")
                } footer: {
                    Text("\(options.kind.summary) Each square is five feet. The same seed and choices always make the same scene.")
                }
                Section {
                    if options.kind != .cave {
                        Picker(amountTitle, selection: $options.rooms) {
                            ForEach([SceneAmount.few, .some, .many]) { Text($0.title).tag($0) }
                        }
                    }
                    if options.kind == .dungeon || options.kind == .building {
                        Picker("Corridors", selection: $options.corridorWidth) {
                            Text("One square wide").tag(1)
                            Text("Two squares wide").tag(2)
                        }
                    }
                    if options.kind == .dungeon {
                        Picker("Loops", selection: $options.loops) {
                            ForEach(SceneAmount.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if options.kind == .dungeon || options.kind == .building {
                        Toggle("Secret doors", isOn: $options.secretDoors)
                    }
                    if !options.kind.isOutdoors {
                        Toggle("Stairs", isOn: $options.stairs)
                    }
                    if options.kind == .building, place.drawnOutline != nil {
                        Toggle("Fill the building’s outline", isOn: $options.fitOutline)
                    }
                } header: {
                    Text("Layout")
                }
                if place.geometry == nil {
                    Section {
                        Label("Put this place on the map first. Its scene map is centred on where it is.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else if existing != nil {
                    Section {
                        Label("This place already has a generated scene. Making it again replaces the places that were made for it, except any you have renamed, moved, linked or written about.", systemImage: "info.circle")
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .themedScreen()
            .themedRow()
            .disabled(isMaking)
            .interactiveDismissDisabled(isMaking)
            .navigationTitle("Generate Scene")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        generation?.cancel()
                        onDone(nil)
                    }
                    .disabled(isMaking && making != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Generate" : "Generate Again") { generation = Task { await generate() } }
                        .disabled(place.geometry == nil || isMaking)
                }
            }
            .onAppear {
                if let saved = existing?.sceneOptions { options = saved }
            }
            .task(id: options) {
                isPreviewing = true
                defer { isPreviewing = false }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                var effective = SceneGenerator.clamped(options)
                effective.squares = plan.squares
                if let made = await SceneGenerator.generateInBackground(effective, outline: plan.outline) { preview = made }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    private func generate() async {
        guard let world = place.world else { return }
        isMaking = true
        making = nil
        defer { isMaking = false }
        let summary = await world.generateScene(for: place, options: options, in: modelContext) { made, total in
            making = (made, total)
        }
        if let summary { onDone(summary.map) }
    }
}

/// The scene as it will be made, with the grid of squares behind it.
struct ScenePreview: View {
    let scene: GeneratedScene?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2)
            Canvas { context, _ in
                context.fill(Path(CGRect(x: origin.x, y: origin.y, width: side, height: side)), with: .color(Color(red: 0.13, green: 0.13, blue: 0.14)))
                guard let scene else { return }
                let scale = Double(side) / scene.extent
                func point(_ p: GridPoint) -> CGPoint { CGPoint(x: origin.x + p.easting * scale, y: origin.y + (scene.extent - p.northing) * scale) }
                let ordered = scene.features.sorted { PlaceStyle.style(forPlaceType: $0.placeType).drawOrder < PlaceStyle.style(forPlaceType: $1.placeType).drawOrder }
                for feature in ordered {
                    let style = PlaceStyle.style(forPlaceType: feature.placeType)
                    switch feature.shape {
                    case .polygon(let points):
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        path.closeSubpath()
                        if let fill = style.fill { context.fill(path, with: .color(Color(style: fill))) }
                        context.stroke(path, with: .color(Color(style: style.stroke)), lineWidth: max(style.lineWidth * 0.6, 1))
                    case .line(let points):
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        context.stroke(path, with: .color(Color(style: style.stroke)), lineWidth: 1.5)
                    case .point(let p):
                        let c = point(p)
                        if feature.placeType == "Stairs" {
                            context.fill(Path(CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(feature.kind == "up" ? .green : .orange))
                        } else {
                            let colour: Color = feature.kind == "secret" ? .purple : Color(red: 0.75, green: 0.5, blue: 0.2)
                            context.fill(Path(CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(colour))
                        }
                    }
                }
                // The grid of squares, faintly, over the top.
                var grid = Path()
                for i in 0...scene.squares {
                    let at = Double(i) / Double(scene.squares) * Double(side)
                    grid.move(to: CGPoint(x: origin.x + at, y: origin.y)); grid.addLine(to: CGPoint(x: origin.x + at, y: origin.y + side))
                    grid.move(to: CGPoint(x: origin.x, y: origin.y + at)); grid.addLine(to: CGPoint(x: origin.x + side, y: origin.y + at))
                }
                context.stroke(grid, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
            }
        }
    }
}

#Preview("A dungeon") {
    var options = SceneOptions()
    options.seed = 4
    options.secretDoors = true
    return ScenePreview(scene: SceneGenerator.generate(options)).frame(width: 520, height: 520)
}

#Preview("A cave") {
    var options = SceneOptions()
    options.kind = .cave
    options.seed = 4
    return ScenePreview(scene: SceneGenerator.generate(options)).frame(width: 520, height: 520)
}

#Preview("A building") {
    var options = SceneOptions()
    options.kind = .building
    options.seed = 4
    options.secretDoors = true
    return ScenePreview(scene: SceneGenerator.generate(options)).frame(width: 520, height: 520)
}

#Preview("An L-shaped building") {
    var options = SceneOptions()
    options.kind = .building
    options.squares = 40
    options.seed = 6
    let s = SceneOptions.squareMetres
    let outline = [(6.0, 8.0), (34, 8), (34, 20), (22, 20), (22, 33), (6, 33)].map { GridPoint(easting: $0.0 * s, northing: $0.1 * s) }
    return ScenePreview(scene: SceneGenerator.generate(options, outline: outline)).frame(width: 520, height: 520)
}

#Preview("A market square") {
    var options = SceneOptions()
    options.kind = .marketSquare
    options.squares = 50
    options.seed = 3
    return ScenePreview(scene: SceneGenerator.generate(options)).frame(width: 520, height: 520)
}

#Preview("A forest clearing") {
    var options = SceneOptions()
    options.kind = .forestClearing
    options.squares = 40
    options.seed = 3
    return ScenePreview(scene: SceneGenerator.generate(options)).frame(width: 520, height: 520)
}

#Preview("A round building") {
    var options = SceneOptions()
    options.kind = .building
    options.squares = 40
    options.seed = 8
    options.secretDoors = true
    let s = SceneOptions.squareMetres
    let outline = (0..<48).map { i -> GridPoint in
        let angle = Double(i) / 48 * 2 * .pi
        return GridPoint(easting: (20 + cos(angle) * 16) * s, northing: (20 + sin(angle) * 16) * s)
    }
    return ScenePreview(scene: SceneGenerator.generate(options, outline: outline)).frame(width: 520, height: 520)
}
