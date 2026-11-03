//
//  NamingStylePicker.swift
//  encounter
//

import SwiftUI

/// Chooses the root language the proper names a generator makes come from.
struct NamingStylePicker: View {
    @Binding var styleID: String

    var body: some View {
        Picker("Names", selection: $styleID) {
            ForEach(RootLanguages.all) { language in Text(language.title).tag(language.id) }
        }
        .help(RootLanguages.language(styleID).summary)
    }
}

/// Chooses root languages and how much of each: a switch per language, and a share for each one that is on.
struct LanguageMixEditor: View {
    @Binding var mix: [LanguageWeight]

    var body: some View {
        ForEach(RootLanguages.all) { language in
            let current = mix.weight(of: language.id)
            Toggle(language.title, isOn: Binding(
                get: { current != nil },
                set: { mix.set(language.id, on: $0) }
            ))
            .help(language.summary)
            if let current {
                Stepper(
                    "Share: \(current)",
                    value: Binding(get: { current }, set: { mix.setWeight($0, of: language.id) }),
                    in: 1...100, step: 10
                )
                .padding(.leading)
            }
        }
    }
}

/// The languages of each realm, so the names in a realm mix the influences it has. A realm can be described in words, and the
/// languages suggested from that.
struct RealmLanguagesEditor: View {
    @Binding var options: WorldOptions
    /// The name each realm has in the preview, by realm number, to head its row.
    var realmNames: [Int: String] = [:]
    /// The realm whose languages are being worked out by the model.
    @State private var suggesting: Int?
    @State private var couldNotSuggest: Int?
    @State private var isDescribing = false
    @State private var couldNotDescribe = false

    private var modelAvailability: RootLanguageDrafter.Availability { RootLanguageDrafter.availability }

    var body: some View {
        HStack {
            Button("Describe Realms", systemImage: "sparkles") { describeRealms() }
                .disabled(isDescribing || modelAvailability != .available || emptyRealms.isEmpty)
                .help("Writes a description for each realm that has none, which you can then edit")
            if isDescribing { ProgressView().controlSize(.small) }
        }
        if couldNotDescribe {
            Text("The descriptions could not be written. Try again.").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(0..<options.realms, id: \.self) { realm in
            DisclosureGroup {
                TextField("What is this realm like?", text: Binding(
                    get: { options.description(forRealm: realm) },
                    set: { options.setDescription($0, forRealm: realm) }
                ), axis: .vertical)
                .lineLimit(2...5)
                HStack {
                    Button("Suggest Languages", systemImage: "sparkles") { suggest(realm) }
                        .disabled(suggesting != nil || modelAvailability != .available || options.description(forRealm: realm).trimmingCharacters(in: .whitespaces).isEmpty)
                    if suggesting == realm { ProgressView().controlSize(.small) }
                }
                if case .unavailable(let reason) = modelAvailability {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if couldNotSuggest == realm {
                    Text("No languages could be suggested from that. Try describing the place or the people.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Reads the description and picks the languages to mix, which you can then change. The description becomes the realm's page.").font(.caption).foregroundStyle(.secondary)
                }
                LanguageMixEditor(mix: Binding(
                    get: { options.languages(forRealm: realm) },
                    set: { options.setLanguages($0, forRealm: realm) }
                ))
            } label: {
                LabeledContent(realmNames[realm] ?? String(localized: "Realm \(realm + 1)"), value: options.languages(forRealm: realm).titles)
            }
        }
    }

    /// The realms with nothing written about them.
    private var emptyRealms: [Int] {
        (0..<options.realms).filter { options.description(forRealm: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Has the model write a description for each realm that has none; ones already written are kept.
    private func describeRealms() {
        let targets = emptyRealms
        guard !targets.isEmpty else { return }
        isDescribing = true
        couldNotDescribe = false
        Task {
            // A realm whose languages were chosen is described as drawing on their cultures.
            let cultures = targets.map { realm in
                options.realmLanguages.indices.contains(realm) && !options.realmLanguages[realm].isEmpty ? options.languages(forRealm: realm).titles : ""
            }
            if let made = try? await RootLanguageDrafter.realmDescriptions(count: targets.count, cultures: cultures), !made.isEmpty {
                for (realm, text) in zip(targets, made) { options.setDescription(text, forRealm: realm) }
            } else {
                couldNotDescribe = true
            }
            isDescribing = false
        }
    }

    private func suggest(_ realm: Int) {
        suggesting = realm
        couldNotSuggest = nil
        let text = options.description(forRealm: realm)
        Task {
            let mix = await LanguageChooser.choose(for: text)
            if let mix { options.setLanguages(mix, forRealm: realm) } else { couldNotSuggest = realm }
            suggesting = nil
        }
    }
}

/// The names of a settlement: the languages of the realm it is in on the world map, which can be changed, or what is chosen here
/// when it isn't in one.
struct SettlementLanguagesEditor: View {
    @Binding var options: SettlementOptions
    /// The languages of the realm the place is in, if it is in one.
    let realm: [LanguageWeight]?

    var body: some View {
        if let realm {
            Toggle("Names from the realm (\(realm.titles))", isOn: Binding(
                get: { options.inheritsRealm },
                set: { inherits in
                    options.inheritsRealm = inherits
                    options.languages = inherits ? realm : options.nameLanguages
                }
            ))
            if !options.inheritsRealm {
                LanguageMixEditor(mix: Binding(get: { options.nameLanguages }, set: { options.languages = $0 }))
            }
        } else {
            // Outside a realm one language is chosen; any left from when the place was in one no longer applies.
            NamingStylePicker(styleID: Binding(
                get: { options.languages.isEmpty ? options.namingStyle : options.languages[0].id },
                set: { options.namingStyle = $0; options.languages = [] }
            ))
        }
    }
}
