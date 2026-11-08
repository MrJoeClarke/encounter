//
//  AboutView.swift
//  encounter
//

import SwiftUI
import CloudKit

/// About Encounter, including the attribution statements the content library's licence requires.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appThemeID") private var themeID = AppTheme.defaultID
    @AppStorage(AppSchema.syncDefaultsKey) private var syncsWithICloud = true
    @State private var iCloudStatus: LocalizedStringResource?
    /// Present in the running app, not in previews.
    @Environment(SyncMonitor.self) private var monitor: SyncMonitor?

    var body: some View {
        NavigationStack {
            Form {
                ThemedSection("Encounter") {
                    Text("A world building tool for tabletop role-playing games.")
                }

                Section {
                    Picker("Theme", selection: $themeID) {
                        ForEach(AppTheme.all) { Text($0.title).tag($0.id) }
                    }
                    Text(AppTheme.theme(id: themeID).summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $syncsWithICloud)
                    if let iCloudStatus {
                        Text(iCloudStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    syncDetails
                } header: {
                    ThemedLabel("iCloud")
                } footer: {
                    Text("Your worlds, pages, maps and images are kept in step on every device signed in to the same iCloud account. Changing this takes effect the next time Encounter opens.")
                }

                Section {
                    ForEach(LibraryEdition.allCases) { edition in
                        if let attribution = Library.shared.attribution(for: edition) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edition.title)
                                    .font(.headline)
                                Text(attribution)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Content Library")
                } footer: {
                    Text("The text of the library has been reformatted for display. Its wording is unchanged.")
                }
            }
            .formStyle(.grouped)
            .themedScreen()
            .themedRow()
            .task { iCloudStatus = await Self.accountStatusText() }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}

extension AboutView {
    /// How sync is doing: whether the store opened with iCloud, and when it last sent and received changes.
    @ViewBuilder
    var syncDetails: some View {
        switch AppSchema.startup {
        case .switchedOff:
            EmptyView()
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .syncing:
            if let monitor {
                LabeledContent("Status", value: monitor.isWorking ? String(localized: "Syncing…") : String(localized: "Up to date"))
                LabeledContent("Last Sent", value: Self.time(monitor.lastExport))
                LabeledContent("Last Received", value: Self.time(monitor.lastImport))
                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private static func time(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Not yet")
    }

    /// Whether this device is signed in to iCloud, in words. Not asked in a preview, which has no iCloud entitlement.
    static func accountStatusText() async -> LocalizedStringResource? {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return nil }
        guard AppSchema.appHasICloudContainer else { return "iCloud sync isn’t set up in this build of the app, so your worlds stay on this device." }
        do {
            switch try await CKContainer(identifier: AppSchema.cloudKitContainerID).accountStatus() {
            case .available: return "This device is signed in to iCloud."
            case .noAccount: return "This device isn’t signed in to iCloud, so your worlds stay on it until it is."
            case .restricted: return "iCloud is restricted on this device."
            case .temporarilyUnavailable: return "iCloud isn’t available right now."
            case .couldNotDetermine: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }
}

#Preview {
    AboutView()
}
