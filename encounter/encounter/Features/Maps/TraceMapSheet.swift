//
//  TraceMapSheet.swift
//  encounter
//

import SwiftUI
import SwiftData
import ImageIO

/// Finds the coloured areas of a picture of a map, shows them over it, and lets the user say what each colour is before places are made.
struct TraceMapSheet: View {
    let map: WorldMap
    /// How many pixels long the picture's longer side is made for working; smaller is quicker and a little rougher.
    var workingSize = MapTracer.Settings().workingSize
    var onFinish: (GeneratedMapSummary?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var image: CGImage?
    @State private var trace: MapTrace?
    @State private var colours: [TracedColour] = []
    @State private var lines: [TracedLine] = []
    @State private var dots: [TracedDot] = []
    @State private var problem: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Group {
                if let problem {
                    ContentUnavailableView("Couldn’t Trace the Map", systemImage: "exclamationmark.triangle", description: Text(problem))
                } else if let image, trace != nil {
                    content(image)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Finding the colours, areas, rivers and roads of the picture. A big picture can take some seconds.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Trace Features")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onFinish(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Places", action: add)
                        .disabled(trace == nil || (!colours.contains { $0.type != .ignore } && !lines.contains { $0.isIncluded } && !dots.contains { $0.isIncluded }))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 640)
        #endif
        .task { await run() }
    }

    private func content(_ image: CGImage) -> some View {
        VStack(spacing: 0) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay { outlines(over: image) }
                .frame(maxWidth: .infinity, maxHeight: 320)
                .padding()
            Divider()
            List {
                Section {
                    ForEach($colours) { $colour in
                        row($colour)
                        ForEach(colour.named.keys.sorted(), id: \.self) { piece in
                            namedPiece(piece, of: $colour)
                        }
                    }
                } header: {
                    Text("Each main colour of the picture, and the names read from its lettering. Choose what each is, or leave it out.")
                        .textCase(nil)
                }
                if !dots.isEmpty {
                    Section {
                        ForEach($dots) { $dot in dotRow($dot) }
                    } header: {
                        Text("Settlements: the dots found in the picture, named from the lettering beside them. Switch off any that are not.")
                            .textCase(nil)
                    }
                }
                if !lines.isEmpty {
                    Section {
                        ForEach($lines) { $line in lineRow($line) }
                    } header: {
                        Text("Rivers (blue lines) and roads (brown lines) found in the picture. Switch off any that are not.")
                            .textCase(nil)
                    }
                }
            }
        }
    }

    /// A row's controls and its name: side by side, or the name under the controls in a narrow window, where they would be squeezed.
    private func twoLine<Controls: View, Name: View>(@ViewBuilder _ controls: () -> Controls, @ViewBuilder name: () -> Name) -> some View {
        let layout = sizeClass == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            HStack { controls() }
            HStack { name() }
        }
    }

    private func row(_ colour: Binding<TracedColour>) -> some View {
        twoLine {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: colour.wrappedValue.red, green: colour.wrappedValue.green, blue: colour.wrappedValue.blue))
                .frame(width: 32, height: 24)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)) }
                .accessibilityHidden(true)
            Picker("Type", selection: colour.type) {
                ForEach(TracedType.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Text(colour.wrappedValue.share, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .foregroundStyle(.secondary)
        } name: {
            TextField("Name", text: colour.name)
                .disabled(colour.wrappedValue.type == .ignore)
        }
    }

    private func dotRow(_ dot: Binding<TracedDot>) -> some View {
        twoLine {
            Toggle("Include", isOn: dot.isIncluded)
                .labelsHidden()
            Image(systemName: "circle.fill")
                .foregroundStyle(.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Picker("Size", selection: dot.kind) {
                Text("City").tag("city")
                Text("Town").tag("town")
                Text("Village").tag("village")
            }
            .labelsHidden()
            .fixedSize()
        } name: {
            TextField("Name", text: dot.name)
                .disabled(!dot.wrappedValue.isIncluded)
            if dot.wrappedValue.isNamed { readNote }
        }
    }

    private func lineRow(_ line: Binding<TracedLine>) -> some View {
        twoLine {
            Toggle("Include", isOn: line.isIncluded)
                .labelsHidden()
            Image(systemName: line.wrappedValue.kind == .river ? "water.waves" : "road.lanes")
                .foregroundStyle(line.wrappedValue.kind == .river ? Color.blue : Color.brown)
                .frame(width: 24)
                .accessibilityHidden(true)
        } name: {
            TextField("Name", text: line.name)
                .disabled(!line.wrappedValue.isIncluded)
            if line.wrappedValue.isNamed { readNote }
        }
    }

    private var readNote: some View {
        Text("read from the picture")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// A piece of a colour's areas that has a name from the lettering on the picture.
    private func namedPiece(_ piece: Int, of colour: Binding<TracedColour>) -> some View {
        twoLine {
            Image(systemName: "text.cursor")
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)
            Picker("Type", selection: Binding(
                get: { colour.wrappedValue.named[piece]?.type ?? colour.wrappedValue.type },
                set: { colour.wrappedValue.named[piece]?.type = $0 == colour.wrappedValue.type ? nil : $0 }
            )) {
                ForEach(TracedType.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        } name: {
            TextField("Name", text: Binding(
                get: { colour.wrappedValue.named[piece]?.name ?? "" },
                set: { colour.wrappedValue.named[piece]?.name = $0 }
            ))
            readNote
        }
    }

    /// The areas that will be made, drawn over the picture.
    private func outlines(over image: CGImage) -> some View {
        Canvas { context, size in
            guard let calibration = map.calibration else { return }
            let sx = size.width / Double(image.width), sy = size.height / Double(image.height)
            for dot in dots where dot.isIncluded {
                let pixel = calibration.pixel(at: dot.point)
                let radius = max(dot.size * sx / 2 + 2, 4)
                let ring = Path(ellipseIn: CGRect(x: pixel.x * sx - radius, y: pixel.y * sy - radius, width: radius * 2, height: radius * 2))
                context.stroke(ring, with: .color(.white), lineWidth: 3)
                context.stroke(ring, with: .color(.red), lineWidth: 1.5)
            }
            for line in lines where line.isIncluded {
                var path = Path()
                for (i, point) in line.points.enumerated() {
                    let pixel = calibration.pixel(at: point)
                    let p = CGPoint(x: pixel.x * sx, y: pixel.y * sy)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(.white), lineWidth: 3.5)
                context.stroke(path, with: .color(line.kind == .river ? .blue : .brown), lineWidth: 1.8)
            }
            for colour in colours where colour.type != .ignore {
                var path = Path()
                for outline in colour.outlines {
                    for (i, point) in outline.enumerated() {
                        let pixel = calibration.pixel(at: point)
                        let p = CGPoint(x: pixel.x * sx, y: pixel.y * sy)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                }
                context.fill(path, with: .color(Color(red: colour.red, green: colour.green, blue: colour.blue).opacity(0.25)))
                context.stroke(path, with: .color(.white), lineWidth: 2.5)
                context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func run() async {
        guard let data = map.imageData, let calibration = map.calibration,
              let source = CGImageSourceCreateWithData(data as CFData, nil), let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            problem = String(localized: "The map has no picture, or has not been calibrated yet.")
            return
        }
        // The areas first, then the lettering on them, which names them and says what some are.
        let size = workingSize
        let found = await Task.detached(priority: .userInitiated) { () -> MapTrace? in
            var settings = MapTracer.Settings()
            settings.workingSize = size
            guard let areas = MapTracer.trace(image: picture, calibration: calibration, settings: settings) else { return nil }
            let read = MapLettering.read(picture)
            let labels = MapLettering.labels(from: read)
            let named = MapTracer.attach(labels, to: areas, calibration: calibration)
            return MapLines.add(to: named, lettering: read, labels: labels, calibration: calibration)
        }.value
        guard let found else {
            problem = String(localized: "No areas could be found in this picture.")
            return
        }
        image = picture
        trace = found
        colours = found.areaColours
        // The model's guess, if it is used: for colours whose names do not already say what they are.
        if MapTypeGuesser.isUsed, let guesses = await MapTypeGuesser.guess(for: colours) {
            for i in colours.indices where colours[i].named[0]?.type == nil {
                if let guess = guesses[colours[i].id] { colours[i].type = guess }
            }
        }
        lines = found.lines
        dots = found.dots
    }

    private func add() {
        guard let world = map.world else { return onFinish(nil) }
        onFinish(world.addTracedPlaces(from: colours, lines: lines, dots: dots, for: map, in: modelContext))
    }
}


#if DEBUG
/// The sample picture of a continent in `Samples/`, if it can be read from the repository, traced at a smaller working size.
@MainActor
private func samplePictureMap() -> (ModelContainer, WorldMap) {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Samples/KnownContinent.png")
    let data = (try? Data(contentsOf: url)) ?? SampleData.solidImage(width: 1500, height: 900, blue: 0.8)
    let map = WorldMap(name: "Known Continent", imageData: data, kind: .world)
    let source = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    map.pixelWidth = source?.width ?? 1500
    map.pixelHeight = source?.height ?? 900
    map.calibration = MapCalibration(anchoringPixel: (0, Double(map.pixelHeight)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 100)
    context.insert(map)
    map.world = world
    map.place = world?.rootPlace
    return (container, map)
}

#Preview("Trace the sample continent") {
    let (container, map) = samplePictureMap()
    TraceMapSheet(map: map, workingSize: 800) { _ in }
        .modelContainer(container)
        .frame(width: 760, height: 900)
}
#endif
