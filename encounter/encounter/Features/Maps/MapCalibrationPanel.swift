//
//  MapCalibrationPanel.swift
//  encounter
//

import SwiftUI

/// Shows whether a map is calibrated and lets the creator calibrate it: mark two points on the map, then say
/// how far apart they are.
struct MapCalibrationPanel: View {
    let map: WorldMap
    /// The points being marked. Only used while `isCalibrating`.
    @Binding var draft: MapCalibrationDraft
    @Binding var isCalibrating: Bool
    /// Which point the next click on the map marks: 1 or 2.
    @Binding var markingPoint: Int

    @State private var isConfirmingRemoval = false

    var body: some View {
        Group {
            if isCalibrating {
                editor
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
            if let calibration = map.calibration {
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

    /// "The map covers 311 mi by 194 mi."
    private func coverage(of calibration: MapCalibration) -> String {
        let unit = DistanceUnit.preferred
        let width = unit.format(metres: Double(map.pixelWidth) * calibration.metresPerPixel)
        let height = unit.format(metres: Double(map.pixelHeight) * calibration.metresPerPixel)
        return String(localized: "The map covers \(width) by \(height).")
    }

    private func begin() {
        markingPoint = 1
        draft = MapCalibrationDraft()
        isCalibrating = true
    }

    // MARK: Entering

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click the map to mark two points that you know the distance between, far apart if you can, such as two towns. Then type how far apart they are.")
                .font(.callout)
            HStack {
                pointButton(1, point: draft.first)
                pointButton(2, point: draft.second)
                Spacer()
                TextField("Distance", value: $draft.distance, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                Text(DistanceUnit.preferred.name)
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
                    if let calibration = draft.worldCalibration(imageHeight: map.pixelHeight) {
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
}

#Preview("Calibrating") {
    var draft = MapCalibrationDraft()
    draft.first = .init(pixelX: 100, pixelY: 800)
    draft.second = .init(pixelX: 1500, pixelY: 100)
    let map = WorldMap(name: "Sword Coast")
    return MapCalibrationPanel(map: map, draft: .constant(draft), isCalibrating: .constant(true), markingPoint: .constant(2))
        .frame(width: 800)
}
