//
//  WorldHomeView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A world's home page: its name, summary, rule system and images, plus export and delete.
struct WorldHomeView: View {
    @Bindable var world: World
    /// Called after the user confirms deletion. The caller leaves this screen and then deletes the world,
    /// so nothing is still showing a deleted world.
    /// Nil where the screen is in a window of its own, which has no list of worlds to return to: the world is deleted from the main window.
    let onDelete: ((World) -> Void)?

    @State private var exportDocument: WorldExportDocument?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isConfirmingDelete = false
    @State private var isEditingCalendar = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $world.name, prompt: Text("Untitled World"))
                    .font(.title2.weight(.semibold))
                    // The root place is named after the world, so renaming the world renames it too.
                    .onChange(of: world.name) { old, _ in world.renameRootPlace(from: old) }
            }

            Section("Summary") {
                TextEditor(text: $world.summary)
                    .frame(minHeight: 140)
            }

            Section {
                Picker("Rule System", selection: Binding(get: { world.systemRaw }, set: { world.choose(systemKey: $0) })) {
                    ForEach(RuleSystems.choices) { system in
                        Text(system.title).tag(system.key)
                    }
                    // A system the app doesn't have stays chosen, so the world keeps it.
                    if !RuleSystems.isKnown(world.systemRaw) {
                        Text(world.systemTitle).tag(world.systemRaw)
                    }
                }
            } footer: {
                Text("The rule system adds attributes to your pages. You can change it at any time without losing data.")
            }

            if let calendar = world.calendar {
                Section {
                    LabeledContent("Calendar") {
                        Text("\(calendar.months.count) months · \(calendar.daysPerYear) days · \(calendar.hoursPerDay) hours a day")
                            .foregroundStyle(.secondary)
                    }
                    Button("Edit Calendar…", systemImage: "calendar") { isEditingCalendar = true }
                } footer: {
                    Text("Events and backstory use this calendar for their dates.")
                }
            }

            ImagesSection(owner: world)

            Section {
                Button("Export World…", systemImage: "square.and.arrow.up", action: export)
            } footer: {
                Text("Saves this world, with its images, as a package you can keep as a backup or import again.")
            }

            if onDelete != nil {
                Section {
                    Button("Delete World…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Home")
        .sheet(isPresented: $isEditingCalendar) {
            if let calendar = world.calendar {
                CalendarEditorView(world: world, calendar: calendar) { isEditingCalendar = false }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .encounterWorld,
            defaultFilename: exportDocument?.suggestedName
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert(
            "Couldn’t Export World",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            presenting: exportError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .alert("Delete World?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { onDelete?(world) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(world.name)” and all of its pages, maps and campaigns will be deleted. This can’t be undone.")
        }
    }

    private func export() {
        exportDocument = WorldExportDocument(world: world)
        isExporting = true
    }
}

#Preview("Home") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world {
            WorldHomeView(world: world) { _ in }
        }
    }
    .frame(width: 900, height: 900)
    .modelContainer(container)
}
