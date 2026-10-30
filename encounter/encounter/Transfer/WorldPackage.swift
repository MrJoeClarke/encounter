//
//  WorldPackage.swift
//  encounter
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A world exported as a package. Declared as an exported type in the app's Info.plist.
    static let encounterWorld = UTType(exportedAs: "com.infography.encounter.world", conformingTo: .package)
}

/// A world archive together with its image files, keyed by file name.
nonisolated struct WorldPackageContents: Sendable {
    var archive: WorldArchive
    var files: [String: Data]
}

nonisolated enum WorldTransferError: LocalizedError {
    /// The folder has no `world.json`.
    case notAWorldPackage
    /// `world.json` exists but couldn't be read as a world.
    case unreadable(String)
    /// The file was written by a newer version of the app.
    case newerFormat(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .notAWorldPackage:
            String(localized: "This isn’t an Encounter world. It has no world.json file.")
        case .unreadable(let detail):
            String(localized: "The world file couldn’t be read. \(detail)")
        case .newerFormat:
            String(localized: "This world was exported by a newer version of Encounter. Update the app to open it.")
        }
    }
}

/// Reads and writes the `.encounterworld` package layout:
///
///     Name.encounterworld/
///         world.json
///         images/
///             <uuid>.jpg …
nonisolated enum WorldPackage {
    static let worldFileName = "world.json"
    static let imagesFolderName = "images"

    /// Readable, diff-friendly JSON with stable key order.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func fileWrapper(for contents: WorldPackageContents) throws -> FileWrapper {
        var children: [String: FileWrapper] = [
            worldFileName: FileWrapper(regularFileWithContents: try makeEncoder().encode(contents.archive)),
        ]
        if !contents.files.isEmpty {
            children[imagesFolderName] = FileWrapper(
                directoryWithFileWrappers: contents.files.mapValues { FileWrapper(regularFileWithContents: $0) }
            )
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    static func contents(of package: FileWrapper) throws -> WorldPackageContents {
        guard package.isDirectory,
              let worldFile = package.fileWrappers?[worldFileName],
              let json = worldFile.regularFileContents
        else { throw WorldTransferError.notAWorldPackage }

        // Check the version first: a newer format may not decode as this version's types.
        struct Header: Decodable { var formatVersion: Int }
        let decoder = makeDecoder()
        do {
            let header = try decoder.decode(Header.self, from: json)
            guard header.formatVersion <= WorldArchive.currentFormatVersion else {
                throw WorldTransferError.newerFormat(found: header.formatVersion, supported: WorldArchive.currentFormatVersion)
            }
            let archive = try decoder.decode(WorldArchive.self, from: json)

            var files: [String: Data] = [:]
            for (name, wrapper) in package.fileWrappers?[imagesFolderName]?.fileWrappers ?? [:] {
                if let data = wrapper.regularFileContents {
                    files[name] = data
                }
            }
            return WorldPackageContents(archive: archive, files: files)
        } catch let error as WorldTransferError {
            throw error
        } catch {
            throw WorldTransferError.unreadable(error.localizedDescription)
        }
    }

    /// Reads a package the user picked, handling the security-scoped access sandboxed apps need.
    @concurrent
    static func read(from url: URL) async throws -> WorldPackageContents {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try contents(of: FileWrapper(url: url))
    }
}
