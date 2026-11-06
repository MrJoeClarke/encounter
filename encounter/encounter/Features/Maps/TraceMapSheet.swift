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
                        Text("Finding the colours and areas of the picture. A big picture can take some seconds.")
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
                        .disabled(trace == nil || !colours.contains { $0.type != .ignore })
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
                    ForEach($colours) { $colour in row($colour) }
                } header: {
                    Text("Each main colour of the picture. Choose what its areas are, or leave them out.")
                        .textCase(nil)
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

    /// The areas that will be made, drawn over the picture.
    private func outlines(over image: CGImage) -> some View {
        Canvas { context, size in
            guard let calibration = map.calibration else { return }
            let sx = size.width / Double(image.width), sy = size.height / Double(image.height)
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
        let found = await Task.detached(priority: .userInitiated) { MapTracer.trace(image: picture, calibration: calibration) }.value
        guard let found else {
            problem = String(localized: "No areas could be found in this picture.")
            return
        }
        image = picture
        trace = found
        colours = found.areaColours
    }

    private func add() {
        guard let world = map.world else { return onFinish(nil) }
        onFinish(world.addTracedPlaces(from: colours, for: map, in: modelContext))
    }
}
