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
    var onFinish: (GeneratedMapSummary?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var image: CGImage?
    @State private var trace: MapTrace?
    @State private var colours: [TracedColour] = []
    @State private var lines: [TracedLine] = []
    @State private var problem: String?

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
                        .disabled(trace == nil || (!colours.contains { $0.type != .ignore } && !lines.contains { $0.isIncluded }))
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

    private func row(_ colour: Binding<TracedColour>) -> some View {
        HStack {
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
            TextField("Name", text: colour.name)
                .disabled(colour.wrappedValue.type == .ignore)
            Text(colour.wrappedValue.share, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func lineRow(_ line: Binding<TracedLine>) -> some View {
        HStack {
            Toggle("Include", isOn: line.isIncluded)
                .labelsHidden()
            Image(systemName: line.wrappedValue.kind == .river ? "water.waves" : "road.lanes")
                .foregroundStyle(line.wrappedValue.kind == .river ? Color.blue : Color.brown)
                .frame(width: 24)
                .accessibilityHidden(true)
            TextField("Name", text: line.name)
                .disabled(!line.wrappedValue.isIncluded)
            if line.wrappedValue.isNamed {
                Text("read from the picture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A piece of a colour's areas that has a name from the lettering on the picture.
    private func namedPiece(_ piece: Int, of colour: Binding<TracedColour>) -> some View {
        HStack {
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
            TextField("Name", text: Binding(
                get: { colour.wrappedValue.named[piece]?.name ?? "" },
                set: { colour.wrappedValue.named[piece]?.name = $0 }
            ))
            Text("read from the picture")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The areas that will be made, drawn over the picture.
    private func outlines(over image: CGImage) -> some View {
        Canvas { context, size in
            guard let calibration = map.calibration else { return }
            let sx = size.width / Double(image.width), sy = size.height / Double(image.height)
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
        let found = await Task.detached(priority: .userInitiated) { () -> MapTrace? in
            guard let areas = MapTracer.trace(image: picture, calibration: calibration) else { return nil }
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
        lines = found.lines
    }

    private func add() {
        guard let world = map.world else { return onFinish(nil) }
        onFinish(world.addTracedPlaces(from: colours, lines: lines, for: map, in: modelContext))
    }
}
