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

/// The languages of each realm, so the names in a realm mix the influences it has.
struct RealmLanguagesEditor: View {
    @Binding var options: WorldOptions

    var body: some View {
        ForEach(0..<options.realms, id: \.self) { realm in
            DisclosureGroup {
                LanguageMixEditor(mix: Binding(
                    get: { options.languages(forRealm: realm) },
                    set: { mix in
                        while options.realmLanguages.count <= realm { options.realmLanguages.append([]) }
                        options.realmLanguages[realm] = mix
                    }
                ))
            } label: {
                LabeledContent("Realm \(realm + 1)", value: options.languages(forRealm: realm).titles)
            }
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
