//
//  CalendarEditorView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Edits a world's calendar: the months, how many hours are in a day, and the days of the week.
struct CalendarEditorView: View {
    let world: World
    @Bindable var calendar: CalendarDefinition
    let onDone: () -> Void

    /// A date to try the calendar out on.
    @State private var sample = InWorldDate()
    @State private var newWeekday = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Menu("Start From…") {
                        ForEach(CalendarPreset.allCases) { preset in
                            Button(String(localized: preset.title)) { calendar.apply(preset) }
                        }
                    }
                } footer: {
                    Text("Replaces the months, days of the week and hours in a day below.")
                }

                Section {
                    Stepper("Hours in a Day: \(calendar.hoursPerDay)", value: $calendar.hoursPerDay, in: 1...100)
                    LabeledContent("Days in a Year", value: calendar.daysPerYear.formatted())
                }

                Section("Months") {
                    ForEach($calendar.months) { $month in
                        HStack {
                            TextField("Name", text: $month.name, prompt: Text("Month"))
                                .labelsHidden()
                            Text("\(month.dayCount) days")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("Days", value: $month.dayCount, in: 1...1000)
                                .labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        // A calendar always has at least one month.
                        guard calendar.months.count > offsets.count else { return }
                        calendar.months.remove(atOffsets: offsets)
                    }
                    .onMove { calendar.months.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Month", systemImage: "plus") {
                        calendar.months.append(CalendarMonth(name: "Month \(calendar.months.count + 1)", dayCount: 30))
                    }
                }

                Section {
                    ForEach(Array(calendar.weekdays.enumerated()), id: \.offset) { index, _ in
                        TextField("Name", text: $calendar.weekdays[index])
                            .labelsHidden()
                    }
                    .onDelete { calendar.weekdays.remove(atOffsets: $0) }
                    .onMove { calendar.weekdays.move(fromOffsets: $0, toOffset: $1) }
                    TextField("Add Day of the Week", text: $newWeekday)
                        .onSubmit {
                            let name = newWeekday.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty { calendar.weekdays.append(name) }
                            newWeekday = ""
                        }
                } header: {
                    Text("Days of the Week")
                } footer: {
                    Text("Optional. Year 0, month 1, day 1 is the first one listed.")
                }

                Section("Try a Date") {
                    InWorldDateField(calendar: calendar, date: $sample)
                    LabeledContent("Reads As", value: calendar.format(sample, style: .long))
                }

                let outside = world.datesOutsideCalendar
                if outside > 0 {
                    Section {
                        Label("\(outside) dates in this world no longer fit the calendar.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("They aren’t changed. Edit those pages, or change the calendar back.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 520)
        // The sample date may no longer exist after the calendar changes.
        .onChange(of: calendar.months) { sample = calendar.clamped(sample) }
        .onChange(of: calendar.hoursPerDay) { sample = calendar.clamped(sample) }
    }
}

#Preview("Calendar") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return Group {
        if let world, let calendar = world.calendar {
            CalendarEditorView(world: world, calendar: calendar) {}
        }
    }
    .frame(width: 520, height: 900)
    .modelContainer(container)
}
