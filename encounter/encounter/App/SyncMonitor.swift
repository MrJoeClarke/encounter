//
//  SyncMonitor.swift
//  encounter
//

import Foundation
import CoreData
import Observation

/// What happened when the app opened its store: whether it is syncing with iCloud, and if not, why.
enum SyncStartup: Equatable {
    case syncing
    /// The user turned sync off.
    case switchedOff
    /// Sync can't start in this build or on this device, with the reason in words.
    case unavailable(String)
}

/// Watches iCloud sync: whether it is working now, when it last sent and received changes, and the last error it met.
/// SwiftData syncs through Core Data's CloudKit container, which posts a notification for each setup, import and export.
@MainActor
@Observable
final class SyncMonitor {
    private(set) var isWorking = false
    private(set) var lastImport: Date?
    private(set) var lastExport: Date?
    private(set) var lastError: String?

    private var observer: NSObjectProtocol?

    /// Starts listening. Call it early, so the events of the app's first moments aren't missed.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type
            let end = event.endDate
            let succeeded = event.succeeded
            let message = event.error.map { Self.describe($0) }
            MainActor.assumeIsolated { self?.record(type: type, end: end, succeeded: succeeded, message: message) }
        }
    }

    private func record(type: NSPersistentCloudKitContainer.EventType, end: Date?, succeeded: Bool, message: String?) {
        guard let end else {
            isWorking = true
            return
        }
        isWorking = false
        if succeeded {
            switch type {
            case .import: lastImport = end
            case .export: lastExport = end
            case .setup: break
            @unknown default: break
            }
            lastError = nil
        } else if let message {
            lastError = message
        }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }
}
