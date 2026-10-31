//
//  MapCalibrationPanel.swift
//  encounter
//

import SwiftUI

/// Shows whether a map is calibrated and lets the creator calibrate it. A world or settlement map: mark two
/// points on the map, then say how far apart they are. A scene map: say how many squares its grid has.
struct MapCalibrationPanel: View {
    let map: WorldMap
    /// The points being marked. Only used while `isCalibrating`.
    @Binding var draft: MapCalibrationDraft
    @Binding var grid: SceneGridDraft
    @Binding var isCalibrating: Bool
    /// Which point the next click on the map marks: 1 or 2.
    @Binding var markingPoint: Int

    @State private var isConfirmingRemoval = false

    var body: some View {
        Group {
            if isCalibrating {
                if map.kind == .scene { sceneEditor } else { pointsEditor }
            } else {
                summary
            }
        }
        .padding()
        .background(.bar)
        .confirmationDialog("Remove Calibration?", isPresented: $isConfirmingRemoval) {
            Button("Remove Calibration", role: .destructive) { map.calibration = nil }
        } message: {
            Text("Places on this map keep their positions, but you will need to calibrate the map again to use it.")
        }
    }

    // MARK: Showing

    @ViewBuilder
    private var summary: some View {
        HStack {
            if !map.canBeCalibrated {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Needs a place", systemImage: "mappin.slash")
                    Text(map.place == nil
                         ? "Choose the place this map shows. It is centred on that place."
                         : "“\(map.place?.title ?? "")” isn’t on a map yet. Put it on the world map first, so this map can be centred on it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let calibration = map.calibration {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Calibrated", systemImage: "checkmark.seal")
                    Text(coverage(of: calibration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Recalibrate…") { begin() }
                Button("Remove…", role: .destructive) { isConfirmingRemoval = true }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Not calibrated", systemImage: "exclamationmark.triangle")
                    Text("Calibrate this map before putting places on it, so a position on it means a position in the world.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Calibrate…") { begin() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// "The map covers 311 mi by 194 mi", in the unit for the map's type.
    private func coverage(of calibration: MapCalibration) -> String {
        let widthMetres = Double(map.pixelWidth) * calibration.metresPerPixel
        let heightMetres = Double(map.pixelHeight) * calibration.metresPerPixel
        let unit = DistanceUnit.forCalibrating(map.kind)
        return String(localized: "The map covers \(unit.format(metres: widthMetres)) by \(unit.format(metres: heightMetres)).")
    }

    private func begin() {
        markingPoint = 1
        draft = MapCalibrationDraft(unit: .forCalibrating(map.kind))
        if map.kind == .scene {
            grid = SceneGridDraft(
                columns: map.gridColumns > 0 ? map.gridColumns : nil,
                rows: map.gridRows > 0 ? map.gridRows : nil
            )
        }
        isCalibrating = true
    }

    // MARK: Entering points (world and settlement maps)

    private var pointsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click the map to mark two points that you know the distance between, far apart if you can. Then type how far apart they are.")
                .font(.callout)
            HStack {
                pointButton(1, point: draft.first)
                pointButton(2, point: draft.second)
                Spacer()
                TextField("Distance", value: $draft.distance, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                Text(draft.unit.name)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let problem = draft.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { isCalibrating = false }
                Button("Apply") {
                    if let calibration = draft.calibration(
                        kind: map.kind, imageWidth: map.pixelWidth, imageHeight: map.pixelHeight, anchor: map.anchorPosition
                    ) {
                        map.calibration = calibration
                        isCalibrating = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.problem != nil)
            }
        }
    }

    private func pointButton(_ number: Int, point: MapCalibrationDraft.Point) -> some View {
        HStack(spacing: 6) {
            Button {
                markingPoint = number
            } label: {
                Label("Point \(number)", systemImage: markingPoint == number ? "scope" : "mappin")
            }
            .buttonStyle(.bordered)
            .tint(markingPoint == number ? .accentColor : .secondary)
            .accessibilityHint("Then click the map to mark it.")

            Image(systemName: point.isMarked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(point.isMarked ? Color.green : Color.secondary)
                .accessibilityLabel(point.isMarked ? "Marked" : "Not marked")
        }
    }

    // MARK: Entering a grid (scene maps)

    private var sceneEditor: some View {
        let problem = grid.problem(imageWidth: map.pixelWidth, imageHeight: map.pixelHeight, anchor: map.anchorPosition)
        let isReady = grid.result(imageWidth: map.pixelWidth, imageHeight: map.pixelHeight, anchor: map.anchorPosition) != nil
        return VStack(alignment: .leading, spacing: 10) {
            Text("Say how many squares the map’s grid has. The scale comes from that, so you don’t need to mark anything.")
                .font(.callout)
            HStack {
                TextField("Across", value: $grid.columns, format: .number.grouping(.never))
                    .frame(maxWidth: 90)
                Text("×")
                TextField("Down", value: $grid.rows, format: .number.grouping(.never))
                    .frame(maxWidth: 90)
                Text("squares")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Each square is")
                    .foregroundStyle(.secondary)
                TextField("Size", value: $grid.squareFeet, format: .number.grouping(.never))
                    .frame(maxWidth: 70)
                Text("feet")
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            HStack {
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { isCalibrating = false }
                Button("Apply") {
                    if let result = grid.result(imageWidth: map.pixelWidth, imageHeight: map.pixelHeight, anchor: map.anchorPosition) {
                        map.calibration = result.calibration
                        map.gridColumns = grid.columns ?? 0
                        map.gridRows = grid.rows ?? 0
                        isCalibrating = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReady)
            }
        }
    }
}

#Preview("Calibrating") {
    var draft = MapCalibrationDraft()
    draft.first = .init(pixelX: 100, pixelY: 800)
    draft.second = .init(pixelX: 1500, pixelY: 100)
    let map = WorldMap(name: "Sword Coast")
    return MapCalibrationPanel(map: map, draft: .constant(draft), grid: .constant(SceneGridDraft()), isCalibrating: .constant(true), markingPoint: .constant(2))
        .frame(width: 800)
}

#Preview("Scene grid") {
    let map = WorldMap(name: "Cellar", kind: .scene)
    return MapCalibrationPanel(map: map, draft: .constant(MapCalibrationDraft()), grid: .constant(SceneGridDraft(columns: 30, rows: 18)), isCalibrating: .constant(true), markingPoint: .constant(1))
        .frame(width: 800)
}
