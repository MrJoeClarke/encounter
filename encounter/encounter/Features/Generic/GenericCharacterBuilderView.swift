//
//  GenericCharacterBuilderView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A guided flow that makes a level 1 character for any system that describes its creation as data: the steps are the
/// system's own, in its order.
struct GenericCharacterBuilderView: View {
    let world: World
    let onCreate: (Page) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model: GenericBuilderModel?

    init(world: World, onCreate: @escaping (Page) -> Void) {
        self.world = world
        self.onCreate = onCreate
        _model = State(initialValue: GenericBuilderModel(world: world))
    }

    var body: some View {
        NavigationStack {
            if let model {
                Form { content(model) }
                    .formStyle(.grouped)
                    .navigationTitle(model.step.title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                    .safeAreaInset(edge: .bottom) { navigationBar(model) }
            } else {
                ContentUnavailableView("No Character Builder", systemImage: "person.badge.plus")
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    // MARK: Steps

    @ViewBuilder
    private func content(_ model: GenericBuilderModel) -> some View {
        let step = model.step
        switch step.kind {
        case .concept:
            Section("Who is the character?") {
                TextField("Name", text: Binding(get: { model.draft.name }, set: { model.draft.name = $0 }))
                TextField("Summary", text: Binding(get: { model.draft.summary }, set: { model.draft.summary = $0 }), axis: .vertical)
                    .lineLimit(1...4)
            }
        case .choose(_, let isRequired), .chooseChild(_, let isRequired):
            chooseContent(model, step: step, isRequired: isRequired)
        case .names(let count, _, let valueText):
            Section {
                ForEach(0..<count, id: \.self) { index in
                    TextField("\(step.title) \(index + 1)", text: Binding(
                        get: { model.draft.names[step.id]?[safe: index] ?? "" },
                        set: { value in
                            var names = model.draft.names[step.id] ?? Array(repeating: "", count: count)
                            while names.count < count { names.append("") }
                            names[index] = value
                            model.draft.names[step.id] = names
                        }
                    ))
                }
            } footer: {
                Text(valueText.isEmpty ? "Name \(count)." : "Name \(count). Each starts at \(valueText).")
            }
        case .pickEntries(_, let count, _, _):
            pickContent(model, step: step, count: count)
        case .numbers(let rule):
            numbersContent(model, step: step, rule: rule)
        case .review:
            reviewContent(model)
        }
    }

    @ViewBuilder
    private func chooseContent(_ model: GenericBuilderModel, step: CreationStep, isRequired: Bool) -> some View {
        let options = model.options(for: step)
        let selected = model.selected(for: step)
        Section {
            if options.isEmpty {
                Text("Nothing to choose from yet.").foregroundStyle(.secondary)
            }
            ForEach(options) { option in
                Button { model.choose(option, for: step) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).foregroundStyle(.primary)
                            if !option.summary.isEmpty {
                                Text(option.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        if option.choice == selected?.choice { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option.choice == selected?.choice ? .isSelected : [])
            }
        } footer: {
            if !isRequired { Text("You can leave this empty.") }
        }
        if let selected {
            Section(selected.name) {
                if !selected.summary.isEmpty { Text(selected.summary) }
                ForEach(Array(selected.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.headline)
                        Text(entry.text).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickContent(_ model: GenericBuilderModel, step: CreationStep, count: Int) -> some View {
        let options = model.options(for: step)
        let picked = Set(model.draft.picks[step.id] ?? [])
        Section {
            if options.isEmpty { Text("Choose the earlier steps first.").foregroundStyle(.secondary) }
            ForEach(options) { option in
                Button { model.togglePick(option, for: step) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).foregroundStyle(.primary)
                            if !option.summary.isEmpty { Text(option.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        Spacer()
                        if let key = option.libraryKey, picked.contains(key) { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option.libraryKey.map(picked.contains) == true ? .isSelected : [])
            }
        } footer: {
            Text("\(picked.count) of \(count) picked.")
        }
    }

    @ViewBuilder
    private func numbersContent(_ model: GenericBuilderModel, step: CreationStep, rule: NumberRule) -> some View {
        Section {
            ForEach(rule.entries, id: \.key) { entry in
                switch rule.method {
                case .assignFrom:
                    Picker(entry.label, selection: Binding(get: { model.draft.numbers[entry.key] ?? 0 }, set: { model.assign($0, to: entry.key, in: rule) })) {
                        ForEach(model.offered(rule), id: \.self) { Text(Self.signed($0)).tag($0) }
                    }
                case .free(let range):
                    Stepper(value: Binding(get: { model.draft.numbers[entry.key] ?? range.lowerBound }, set: { model.draft.numbers[entry.key] = $0 }), in: range) {
                        LabeledContent(entry.label, value: Self.signed(model.draft.numbers[entry.key] ?? range.lowerBound))
                    }
                }
            }
        } footer: {
            if case .assignFrom(let available) = rule.method {
                Text("Give each one of \(available.sorted(by: >).map(Self.signed).joined(separator: ", ")).")
            }
        }
    }

    @ViewBuilder
    private func reviewContent(_ model: GenericBuilderModel) -> some View {
        let plan = model.plan
        Section("Character") {
            LabeledContent("Name", value: model.draft.name.isEmpty ? "—" : model.draft.name)
            ForEach(model.flow.steps) { step in
                switch step.kind {
                case .choose, .chooseChild: LabeledContent(step.title, value: model.selected(for: step)?.name ?? "—")
                default: EmptyView()
                }
            }
        }
        ForEach(model.flow.steps) { step in
            if case .names = step.kind {
                Section(step.title) { ForEach((model.draft.names[step.id] ?? []).filter { !$0.isEmpty }, id: \.self) { Text($0) } }
            }
            if case .pickEntries(_, _, _, _) = step.kind {
                Section(step.title) {
                    ForEach(model.draft.picks[step.id] ?? [], id: \.self) { key in Text(Library.shared.entry(forKey: key)?.name ?? key) }
                }
            }
            if case .numbers(let rule) = step.kind {
                Section(step.title) {
                    ForEach(rule.entries, id: \.key) { entry in
                        LabeledContent(entry.label, value: Self.signed(model.draft.numbers[entry.key] ?? 0))
                    }
                }
            }
        }
        if !plan.derived.isEmpty {
            Section("Starting numbers") {
                ForEach(plan.derived.keys.sorted(), id: \.self) { key in
                    LabeledContent(model.system.attributes.first { $0.key == key }.map { String(localized: $0.label) } ?? key, value: Int(plan.derived[key] ?? 0).formatted())
                }
            }
        }
        if !plan.problems.isEmpty {
            Section("Still to do") {
                ForEach(plan.problems, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }
    }

    private static func signed(_ number: Int) -> String { number >= 0 ? "+\(number)" : "−\(-number)" }

    // MARK: Moving between steps

    private func navigationBar(_ model: GenericBuilderModel) -> some View {
        HStack {
            Button("Back") { model.goBack() }.disabled(!model.canGoBack)
            Spacer()
            Text("Step \(model.stepIndex + 1) of \(model.flow.steps.count)").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if model.canGoForward {
                Button("Next") { model.goForward() }.buttonStyle(.borderedProminent)
            } else {
                Button("Create Character") {
                    if let page = model.create(in: modelContext) {
                        onCreate(page)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.plan.isReady)
            }
        }
        .padding()
        .background(.bar)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview("Daggerheart builder") {
    let data = GenericPreviewData.make()
    return Group { if let data { GenericCharacterBuilderView(world: data.world) { _ in }.modelContainer(data.container) } }
}
