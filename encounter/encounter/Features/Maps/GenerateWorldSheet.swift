//
//  GenerateWorldSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Chooses what a world is like and shows the result before it is made. Making it adds the world map, with a place for the
/// sea, each realm, the forests and mountains, the rivers and roads, and each settlement.
struct GenerateWorldSheet: View {
    let world: World
    let onDone: (WorldMap?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var options = {
        var fresh = WorldOptions()
        fresh.seed = UInt64.random(in: 1...999_999)
        return fresh
    }()
    @State private var preview: GeneratedWorld?
    @State private var isPreviewing = false
    @State private var making: (made: Int, total: Int)?
    @State private var isMaking = false
    @State private var generation: Task<Void, Never>?
    /// The location that the next tap on the preview places.
    @State private var placing: WorldLocation.ID?

    private let unit = DistanceUnit.forCalibrating(.world)

    private var existing: WorldMap? {
        world.rootPlace.flatMap { root in
            (world.maps ?? []).first { $0.place === root && $0.isVector && $0.generatorData != nil && !$0.isDeleted }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WorldPreview(world: preview, placing: placing != nil, onTap: place)
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
                                        Text("Laying out the world…")
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
                        Text("^[\(preview.features(of: "Settlement").count) settlement](inflect: true), ^[\(preview.features(of: "Region").count) realm area](inflect: true), ^[\(preview.features(of: "Road").count) road](inflect: true), ^[\(preview.features(of: "River").count) river](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    distanceField("Width", metres: $options.width, minimum: 20_000)
                    Picker("Land", selection: $options.shape) {
                        ForEach(WorldShape.allCases) { Text($0.title).tag($0) }
                    }
                    if options.shape == .archipelago {
                        Picker("Islands", selection: $options.islands) {
                            ForEach(WorldIslands.allCases.filter { $0 != .none }) { Text($0.title).tag($0) }
                        }
                    }
                    Stepper("Realms: \(options.realms)", value: $options.realms, in: 1...8)
                    NamingStylePicker(styleID: $options.namingStyle)
                    RealmLanguagesEditor(options: $options)
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
                    Text("World")
                } footer: {
                    Text("\(options.shape.summary) Each realm has a capital city. Names in a realm come from the languages chosen for it, which start as the one chosen for Names. The same seed and choices always make the same world.")
                }
                Section {
                    Picker("Mountains", selection: $options.mountains) {
                        ForEach(WorldAmount.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Forests", selection: $options.forests) {
                        ForEach(WorldAmount.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Rivers: \(options.rivers)", value: $options.rivers, in: 0...12)
                } header: {
                    Text("Land")
                }
                Section {
                    distanceField("Between cities", metres: $options.citySpacing, minimum: 5_000)
                    distanceField("Between towns", metres: $options.townSpacing, minimum: 3_000)
                    distanceField("Between villages", metres: $options.villageSpacing, minimum: 2_000)
                    Toggle("Keep settlements already on the map", isOn: $options.includeExisting)
                } header: {
                    Text("Settlements")
                } footer: {
                    Text("About how far apart places of each kind are. Roads join them, and rivers and mountains slow the roads. Settlements are pins; make a settlement’s own map from its page.")
                }
                Section {
                    ForEach($options.locations) { $location in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Name", text: $location.name, prompt: Text("Chosen for you"))
                                Picker("Kind", selection: $location.kind) {
                                    ForEach(WorldLocation.Kind.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden()
                                .fixedSize()
                                Button("Remove", systemImage: "minus.circle") { remove(location) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                            }
                            HStack {
                                if location.kind == .city { Toggle("Capital", isOn: $location.isCapital) }
                                Spacer()
                                if location.east != nil {
                                    Button("Choose for Me") { location.east = nil; location.north = nil }
                                }
                                Button(placing == location.id ? "Tap the Preview" : (location.east == nil ? "Place on Preview" : "Move")) {
                                    placing = placing == location.id ? nil : location.id
                                }
                            }
                            .font(.callout)
                        }
                    }
                    Button("Add Location", systemImage: "plus") { options.locations.append(WorldLocation()) }
                } header: {
                    Text("Locations")
                } footer: {
                    Text("Places you want in the world. One with no spot is put where it suits its kind. A capital city takes one of the realms.")
                }
                if let existing {
                    Section {
                        Label("This world already has a generated map. Making it again replaces the places that were made for it, except any you have renamed, moved, linked or written about.", systemImage: "info.circle")
                            .font(.callout)
                            .id(existing.id)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isMaking)
            .interactiveDismissDisabled(isMaking)
            .navigationTitle("Generate World")
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
                        .disabled(isMaking || world.rootPlace == nil)
                }
            }
            .onAppear {
                if let saved = existing?.worldOptions { options = saved }
            }
            // The layout is worked out away from the screen a moment after the last change.
            .task(id: options) {
                isPreviewing = true
                defer { isPreviewing = false }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let fixed = world.fixedSettlements(excludingUneditedFrom: existing)
                if let made = await WorldGenerator.generateInBackground(options, fixed: fixed) { preview = made }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 700)
        #endif
    }

    /// A distance typed in the world's unit and kept in metres.
    private func distanceField(_ title: LocalizedStringKey, metres: Binding<Double>, minimum: Double) -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, value: Binding(
                    get: { (metres.wrappedValue / unit.metres * 10).rounded() / 10 },
                    set: { metres.wrappedValue = max(minimum, $0 * unit.metres) }
                ), format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text(unit.name)
            }
        }
    }

    private func remove(_ location: WorldLocation) {
        options.locations.removeAll { $0.id == location.id }
        if placing == location.id { placing = nil }
    }

    /// A tap on the preview puts the location being placed there.
    private func place(at spot: GridPoint) {
        guard let id = placing, let index = options.locations.firstIndex(where: { $0.id == id }), options.width > 0 else { return }
        options.locations[index].east = max(0, min(1, spot.easting / options.width))
        options.locations[index].north = max(0, min(1, spot.northing / options.width))
        placing = nil
    }

    private func generate() async {
        isMaking = true
        making = nil
        defer { isMaking = false }
        let summary = await world.generateWorld(options: options, in: modelContext) { made, total in
            making = (made, total)
        }
        if let summary { onDone(summary.map) }
    }
}

/// The world as it will be made, drawn small: the sea, the realms in their own colours, forests, mountains, rivers, roads and
/// settlements. A tap reports where on the map it was, in metres.
struct WorldPreview: View {
    let world: GeneratedWorld?
    var placing = false
    var onTap: ((GridPoint) -> Void)?

    private static func realmColour(_ kind: String) -> Color {
        let index = Int(kind.split(separator: " ").last ?? "0") ?? 0
        let hues: [Double] = [0.08, 0.58, 0.83, 0.15, 0.97, 0.45, 0.7, 0.3]
        return Color(hue: hues[index % hues.count], saturation: 0.45, brightness: 0.8)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2)
            Canvas { context, _ in
                context.fill(Path(CGRect(x: origin.x, y: origin.y, width: side, height: side)), with: .color(Color(red: 0.13, green: 0.13, blue: 0.14)))
                guard let world else { return }
                let scale = Double(side) / world.extent
                func point(_ p: GridPoint) -> CGPoint { CGPoint(x: origin.x + p.easting * scale, y: origin.y + (world.extent - p.northing) * scale) }
                let ordered = world.features.sorted { PlaceStyle.style(forPlaceType: $0.placeType).drawOrder < PlaceStyle.style(forPlaceType: $1.placeType).drawOrder }
                for feature in ordered {
                    let style = PlaceStyle.style(forPlaceType: feature.placeType)
                    switch feature.shape {
                    case .polygon(let points):
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        path.closeSubpath()
                        if feature.placeType == "Region" {
                            context.fill(path, with: .color(Self.realmColour(feature.kind).opacity(0.55)))
                            context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 0.8)
                        } else {
                            if let fill = style.fill { context.fill(path, with: .color(Color(style: fill))) }
                            context.stroke(path, with: .color(Color(style: style.stroke)), lineWidth: 0.6)
                        }
                    case .line(let points):
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: point(first))
                        for p in points.dropFirst() { path.addLine(to: point(p)) }
                        context.stroke(path, with: .color(Color(style: style.stroke)), style: StrokeStyle(lineWidth: feature.placeType == "River" ? 1.6 : 1, lineCap: .round, lineJoin: .round))
                    case .point(let p):
                        let c = point(p)
                        let radius: CGFloat = feature.kind == "capital" ? 5 : feature.kind == "city" ? 3.5 : feature.kind == "town" ? 2.5 : 1.8
                        let dot = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(feature.kind == "capital" ? .yellow : .white))
                        context.stroke(dot, with: .color(.black), lineWidth: 0.8)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let world, let onTap, side > 0 else { return }
                let x = (location.x - origin.x) / side, y = (location.y - origin.y) / side
                guard (0...1).contains(x), (0...1).contains(y) else { return }
                onTap(GridPoint(easting: x * world.extent, northing: (1 - y) * world.extent))
            }
            .overlay(alignment: .topLeading) {
                if placing { Text("Tap where it should be").font(.caption).padding(4).background(.regularMaterial, in: Capsule()).padding(6) }
            }
        }
    }
}

#Preview("Generate a world") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let world = World(name: "Aldara")
    context.insert(world)
    world.ensureRootPlace(in: context)
    return GenerateWorldSheet(world: world) { _ in }
        .modelContainer(container)
}

#Preview("A world") {
    var options = WorldOptions()
    options.seed = 7
    options.realms = 4
    return WorldPreview(world: WorldGenerator.generate(options))
        .frame(width: 520, height: 520)
}
