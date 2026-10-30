//
//  WorldExportDocument.swift
//  encounter
//

import SwiftUI
import UniformTypeIdentifiers

/// The document handed to `fileExporter` to write a world as a package.
@MainActor
final class WorldExportDocument: WritableDocument {
    static let writableContentTypes: [UTType] = [.encounterWorld]

    private let world: World

    init(world: World) {
        self.world = world
    }

    /// The file name offered in the save dialog, without the extension.
    var suggestedName: String {
        world.name.isEmpty ? String(localized: "Untitled World") : world.name
    }

    nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<WorldPackageContents> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            try WorldPackage.fileWrapper(for: snapshot)
        }
    }

    func snapshot(contentType: UTType) async throws -> sending WorldPackageContents {
        WorldExporter.makeContents(of: world)
    }
}
