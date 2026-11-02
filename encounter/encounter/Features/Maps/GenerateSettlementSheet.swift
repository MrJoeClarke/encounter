//
//  GenerateSettlementSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Chooses what a settlement is like and shows the result before it is made. Making it adds a map of the place, and a
/// place for each district, street and building on it.
struct GenerateSettlementSheet: View {
    let place: Page
    let onDone: (WorldMap?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var options = SettlementOptions(seed: UInt64.random(in: 1...999_999))
    @State private var preview: GeneratedSettlement?
    /// Whether a preview is being worked out, which is done away from the screen so a city doesn't freeze it.
    @State private var isPreviewing = false
    /// How far making the places has got, while it is happening.
    @State private var making: (made: Int, total: Int)?
    @State private var isMaking = false
    @State private var generation: Task<Void, Never>?

    /// Whether the place has an outline to fill, which decides how big the settlement is.
    private var usesOutline: Bool { place.drawnOutline != nil }

    private var existing: WorldMap? {
        (place.world?.maps ?? []).first { $0.place === place && $0.isVector && $0.generatorData != nil && !$0.isDeleted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettlementPreview(settlement: preview, onTap: handleTap)
                        .frame(height: 300)
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
                                        Text("Laying out the settlement…")
                                    }
                                }
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            } else if isPreviewing {
                                ProgressView()
                                    .controlSize(.large)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    if let preview {
                        let quarters = preview.features(of: "District").count + preview.features(of: "Garden").count
                        let streets = preview.features(of: "Road").count + preview.features(of: "Street").count
                        Text("^[\(streets) street](inflect: true), ^[\(quarters) quarter](inflect: true), ^[\(preview.features(of: "Landmark").count) landmark](inflect: true), about \(Int(preview.extent)) metres across")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if usesOutline {
                        Label("Fills the outline you drew for this place on the map above. Its size sets how big the settlement is.", systemImage: "square.dashed")
                            .font(.callout)
                    } else {
                        Picker("Size", selection: $options.size) {
                            ForEach(SettlementOptions.Size.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Streets", selection: $options.layout) {
                        ForEach(SettlementOptions.Layout.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Wall", isOn: $options.hasWalls)
                    Toggle("River", isOn: $options.hasRiver)
                    LabeledContent("Seed") {
                        HStack {
                            TextField("Seed", value: $options.seed, format: .number.grouping(.never))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Button("New Seed", systemImage: "dice") { options.seed = UInt64.random(in: 1...999_999) }
                                .labelStyle(.iconOnly)
                        }
                    }
                } header: {
                    Text("Settlement")
                } footer: {
                    Text("The same seed and choices always make the same settlement.")
                }
                Section {
                    Text("Tap the edge of the preview to add a gate, tap a gate to take it away, and tap inside to move the main square.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LabeledContent("Gates") {
                        HStack {
                            Text(options.gates.isEmpty ? String(localized: "Chosen for you (\(preview?.gates.count ?? 0))") : String(localized: "\(options.gates.count) placed"))
                                .foregroundStyle(.secondary)
                            Button("Choose for Me") { options.gates = [] }.disabled(options.gates.isEmpty)
                        }
                    }
                    LabeledContent("Main square") {
                        HStack {
                            Text(options.square == nil ? String(localized: "Near the middle") : String(localized: "Placed")).foregroundStyle(.secondary)
                            Button("Centre It") { options.square = nil }.disabled(options.square == nil)
                        }
                    }
                } header: {
                    Text("Gates and Main Square")
                }
                Section {
                    Toggle("Choose for Me", isOn: Binding(
                        get: { options.quarters == nil },
                        set: { automatic in
                            options.quarters = automatic ? nil : SettlementGenerator.TownMaker.automaticQuarters(for: options.size, hasRiver: options.hasRiver)
                        }
                    ))
                    if let chosen = options.quarters {
                        ForEach(Quarter.allCases) { quarter in
                            Toggle(quarter.title, isOn: Binding(
                                get: { chosen.contains(quarter) },
                                set: { on in
                                    var list = chosen.filter { $0 != quarter }
                                    if on { list.append(quarter) }
                                    options.quarters = list
                                }
                            ))
                            .disabled(quarter == .harbour && !options.hasRiver)
                        }
                        if !options.hasRiver { Text("A harbour needs a river.").font(.caption).foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("Quarters")
                } footer: {
                    Text("Each takes the wards that suit it: the wealthy and the temple near the square, craftsmen near the gates and the river, slums out by the wall.")
                }
                Section {
                    ForEach(Landmark.allCases) { landmark in
                        Toggle(landmark.title, isOn: Binding(
                            get: { options.landmarks.contains(landmark) },
                            set: { on in
                                options.landmarks.removeAll { $0 == landmark }
                                if on { options.landmarks.append(landmark) }
                            }
                        ))
                    }
                } header: {
                    Text("Landmarks")
                } footer: {
                    Text("A castle takes a whole ward. The others take the ground they need in a ward that suits them.")
                }
                Section {
                    Toggle("Inns and Taverns", isOn: $options.inns)
                    Toggle("Merchants", isOn: $options.merchants)
                } header: {
                    Text("Inns and Merchants")
                } footer: {
                    Text("A number to suit the size, facing the streets and spread round the settlement. Other buildings are for you to add.")
                }
                if place.geometry == nil {
                    Section {
                        Label("Put this place on the world map first. Its map is centred on where it is.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else if existing != nil {
                    Section {
                        Label("This place already has a generated map. Making it again replaces the places that were made for it, except any you have renamed, moved, linked or written about.", systemImage: "info.circle")
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isMaking)
            .interactiveDismissDisabled(isMaking)
            .navigationTitle("Generate Settlement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Stops the layout if it is still being worked out. Once places are being made it can't stop.
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
                if let saved = existing?.settlementOptions { options = saved }
            }
            // The layout is worked out on a background thread a moment after the last change, so typing a seed or
            // flicking a switch doesn't start a new one for every key.
            .task(id: options) {
                isPreviewing = true
                defer { isPreviewing = false }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let plan = World.settlementPlan(for: place, options: options)
                if let made = await SettlementGenerator.generateInBackground(options, outline: plan.outline, extent: plan.extent) {
                    preview = made
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    /// A tap on the preview adds a gate near the edge, takes away a gate that was tapped, or moves the main square.
    private func handleTap(_ spot: GridPoint, _ frame: PreviewFrame) {
        guard let preview, preview.radius > 0 else { return }
        let tapped = frame.point(spot)
        let dx = spot.easting - preview.centre.easting, dy = spot.northing - preview.centre.northing
        // Gates are kept as bearings. If they were chosen for the creator, they become the creator's to change.
        var bearings = options.gates.isEmpty
            ? preview.gates.map { atan2($0.northing - preview.centre.northing, $0.easting - preview.centre.easting) }
            : options.gates.map(\.bearing)
        if let near = preview.gates.indices.first(where: { hypot(frame.point(preview.gates[$0]).x - tapped.x, frame.point(preview.gates[$0]).y - tapped.y) < 14 }) {
            // At least one gate stays.
            guard bearings.count > 1, bearings.indices.contains(near) else { return }
            bearings.remove(at: near)
            options.gates = bearings.map { SettlementGate(bearing: $0) }
        } else if hypot(dx, dy) > preview.radius * 0.7 {
            bearings.append(atan2(dy, dx))
            options.gates = bearings.map { SettlementGate(bearing: $0) }
        } else {
            options.square = SquareSpot(east: max(-0.8, min(0.8, dx / preview.radius)), north: max(-0.8, min(0.8, dy / preview.radius)))
        }
    }

    private func generate() async {
        guard let world = place.world else { return }
        isMaking = true
        making = nil
        defer { isMaking = false }
        let summary = await world.generateSettlement(for: place, options: options, in: modelContext) { made, total in
            making = (made, total)
        }
        if let summary { onDone(summary.map) }
    }
}

/// How a settlement is fitted into a view: the part of the map shown, and how it is scaled and where it sits. Drawing and
/// tapping use the same one, so a tap lands on the point it was drawn at.
struct PreviewFrame {
    let minX: Double
    let maxY: Double
    let scale: Double
    let origin: CGPoint
    let side: CGFloat

    init(_ settlement: GeneratedSettlement, size: CGSize) {
        // Fit the settlement itself, not the whole map, so a small one isn't lost in the middle of the river and roads.
        var xs: [Double] = [], ys: [Double] = []
        for ward in settlement.wards { xs += ward.map(\.easting); ys += ward.map(\.northing) }
        if xs.isEmpty {
            for feature in settlement.features {
                switch feature.shape {
                case .polygon(let p), .line(let p): xs += p.map(\.easting); ys += p.map(\.northing)
                case .point(let p): xs.append(p.easting); ys.append(p.northing)
                }
            }
        }
        let margin = ((xs.max() ?? 0) - (xs.min() ?? 0)) * 0.18
        let low = max((xs.min() ?? 0) - margin, 0), high = min((xs.max() ?? settlement.extent) + margin, settlement.extent)
        let bottom = max((ys.min() ?? 0) - margin, 0), top = min((ys.max() ?? settlement.extent) + margin, settlement.extent)
        let span = max(high - low, top - bottom, 1)
        side = min(size.width, size.height)
        scale = Double(side) / span
        origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        minX = low
        maxY = top
    }

    func point(_ p: GridPoint) -> CGPoint { CGPoint(x: origin.x + (p.easting - minX) * scale, y: origin.y + (maxY - p.northing) * scale) }

    /// The place on the map under a point in the view.
    func location(of point: CGPoint) -> GridPoint {
        GridPoint(easting: minX + Double(point.x - origin.x) / scale, northing: maxY - Double(point.y - origin.y) / scale)
    }
}

/// A generated settlement drawn small, in the styles the map uses, with the gates and main square marked. A tap is reported
/// as a place on the map, for adding gates and moving the square.
struct SettlementPreview: View {
    let settlement: GeneratedSettlement?
    var onTap: ((GridPoint, PreviewFrame) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let settlement else { return }
                let frame = PreviewFrame(settlement, size: size)
                let point = frame.point
                context.fill(Path(CGRect(origin: frame.origin, size: CGSize(width: frame.side, height: frame.side))), with: .color(Color(red: 0.13, green: 0.13, blue: 0.14)))
                // The wards the settlement was cut into, faintly, under everything.
                for ward in settlement.wards {
                    guard let first = ward.first else { continue }
                    var path = Path()
                    path.move(to: point(first))
                    for p in ward.dropFirst() { path.addLine(to: point(p)) }
                    path.closeSubpath()
                    context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                }
                let ordered = settlement.features.sorted { PlaceStyle.style(forPlaceType: $0.placeType).drawOrder < PlaceStyle.style(forPlaceType: $1.placeType).drawOrder }
                for feature in ordered {
                    let style = PlaceStyle.style(forPlaceType: feature.placeType)
                    var path = Path()
                    switch feature.shape {
                    case .polygon(let points):
                        guard let first = points.first else { continue }
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        path.closeSubpath()
                        if let fill = style.fill { context.fill(path, with: .color(Color(style: fill))) }
                        context.stroke(path, with: .color(Color(style: style.stroke)), lineWidth: max(style.lineWidth * 0.5, 0.5))
                    case .line(let points):
                        guard let first = points.first else { continue }
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        context.stroke(path, with: .color(Color(style: style.stroke)), style: StrokeStyle(lineWidth: max(style.lineWidth * 0.6, 0.8), lineCap: .round, lineJoin: .round))
                    case .point:
                        continue
                    }
                }
                // The main square and the gates.
                if let square = settlement.square {
                    let c = point(square)
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 1.5)
                }
                for gate in settlement.gates {
                    let c = point(gate)
                    context.fill(Path(CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.cyan))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let settlement, let onTap else { return }
                let frame = PreviewFrame(settlement, size: geometry.size)
                onTap(frame.location(of: location), frame)
            }
        }
        .accessibilityLabel("Preview of the settlement")
    }
}

extension Color {
    init(style color: StyleColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

#Preview("Generate a settlement") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview")
    context.insert(world)
    let town = world.addPage(kind: .place, in: context)
    town.title = "Harrowgate"
    _ = town.setGeometry(.point(GridPoint(easting: 50_000, northing: 50_000)))
    return GenerateSettlementSheet(place: town) { _ in }
        .modelContainer(container)
}

#Preview("Generate inside an outline") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview")
    context.insert(world)
    let town = world.addPage(kind: .place, in: context)
    town.title = "Harrowgate"
    _ = town.setGeometry(.polygon([
        GridPoint(easting: 50_000, northing: 50_000), GridPoint(easting: 50_700, northing: 50_050), GridPoint(easting: 50_900, northing: 50_450),
        GridPoint(easting: 50_400, northing: 50_800), GridPoint(easting: 50_000, northing: 50_500),
    ]))
    return GenerateSettlementSheet(place: town) { _ in }
        .modelContainer(container)
}

#Preview("Three layouts") {
    HStack(spacing: 8) {
        ForEach(SettlementOptions.Layout.allCases) { layout in
            VStack {
                SettlementPreview(settlement: SettlementGenerator.generate(SettlementOptions(size: .town, layout: layout, hasWalls: true, hasRiver: true, seed: 12)))
                    .frame(width: 420, height: 420)
                Text(layout.title)
            }
        }
    }
    .padding()
}

#Preview("City with quarters and landmarks") {
    SettlementPreview(settlement: SettlementGenerator.generate(SettlementOptions(
        size: .city, layout: .organic, hasWalls: true, hasRiver: true, seed: 8,
        landmarks: [.cathedral, .castle, .university, .guildhall, .arena, .library, .wizardsTower, .prison, .infirmary]
    )))
    .frame(width: 900, height: 900)
}
