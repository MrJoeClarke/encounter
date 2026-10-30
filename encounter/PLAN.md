# Encounter: World Building for TTRPGs

A multiplatform (macOS, iOS, iPadOS) SwiftUI app for building and browsing campaign worlds. D&D 5e comes first. The design keeps other systems easy to add.

## 1. Goals (v1)

1. Typed information pages: Character (playable / NPC / monster), Place, Event, Item, Organisation, Race/Species/Ancestry.
2. Each type has its own attributes. Choosing a rule system adds that system's attributes.
3. Pages link to each other, including inline `@` mentions.
4. Places form a hierarchy (region, settlement, building).
5. Upload a map image, show it interactively, and pin places on it.
6. Events are either backstory or part of a campaign. Linked events produce timelines and character movement.
7. Search across everything.

8. Multiple images per page with a default image, and a custom in-world calendar per world.
9. JSON import and export of a world.

**Non-goals for v1:** CloudKit sync, sharing or collaboration, player and DM visibility controls, other TTRPG systems, other import/export formats (Markdown, VTT), a combat tracker.

## 2. Technical Decisions

| Area | Decision | Reason |
|---|---|---|
| UI | SwiftUI only. `NavigationSplitView` is the shell and adapts to Mac, iPad and iPhone. | One codebase, native behaviour on each platform. |
| Persistence | SwiftData, with a CloudKit-compatible schema from day one. | CloudKit can be enabled later with no migration pain. |
| Concurrency | async/await and `@Observable`. No Combine. | Project guideline. |
| Tests | Swift Testing for unit tests, XCUIAutomation for UI tests. | Project guideline. |
| Targets | One multiplatform app target. Minimum OS is 26 on iOS, iPadOS and macOS. | Gives `TextEditor` with `AttributedString` and current SwiftUI APIs. |

**CloudKit-compatible schema rules.** These apply to every model from the start:
- No `@Attribute(.unique)`.
- Every property has a default or is optional.
- All relationships are optional, with explicit inverses.
- Large blobs (map images) use `@Attribute(.externalStorage)`.
- Enums are stored as raw-value strings.

Later, enabling CloudKit means adding the iCloud capability and a `ModelConfiguration(cloudKitDatabase:)`. The schema needs no changes.

## 3. Domain Model

```
World                     a top-level container (e.g. "Faerûn", "My Homebrew"). A creator can have many.
 ├─ system: RuleSystemID  (.none, .dnd5e, ...), one per world
 ├─ Campaign[]            (a World can host several campaigns)
 ├─ Page[]                (all content)
 ├─ WorldMap[]
 └─ CalendarDefinition    (custom in-world calendar, see below)

CalendarDefinition
 ├─ hoursPerDay: Int                (e.g. 24, but editable)
 ├─ months: [(name, dayCount)]      (any number of months; each month has its own name and
 │                                   editable day count)
 ├─ weekdays: [String]              (optional)
 └─ eras: [(name, suffix)]          (optional, e.g. "Dale Reckoning" / "DR")
                                    Years are fixed length (no leap rules in v1).

Calendar creation flow: choose hours per day, number of months, and a default days per month,
then edit each month's name and day count individually. Days per year is the sum of the months.
Editing a calendar that already has dated events keeps stored dates valid (see below) and warns
if a change would push an existing date out of range.

InWorldDate               stored as year, month index, day, hour (and optional minute), plus era.
                          Sortable via a computed absolute hour number from the world's calendar.
                          Formatting is by calendar.

Page                      one entity for all page types, discriminated by `kind`
 ├─ id, title, summary, kind
 ├─ characterRole: .playable | .nonPlayable   (only for kind == .character; monsters are
 │                  non-playable characters, with the "monster" distinction coming from tags or
 │                  a creature-type attribute for now)
 ├─ images: [PageImage]             (many; exactly one flagged as default)
 ├─ body: AttributedString          (rich text with @mention runs)
 ├─ attributes: [String: AttributeValue]   (Codable, key-addressed)
 ├─ parent: Page?                   (hierarchy; used mainly for Places)
 ├─ tags: [String]
 └─ outgoing: [PageLink], incoming: [PageLink]

PageImage                 page, image data (externalStorage), caption, sortOrder, isDefault
                          Setting a new default clears the previous one. Deleting the default
                          promotes the next image. Thumbnails are generated for lists.

PageLink                  source Page, target Page, role (e.g. "participant", "location", "member")
                          Rebuilt from @mentions and from structured fields.

Event (data on Page.kind == .event)
 ├─ origin: .backstory | .campaign(Campaign)
 ├─ when: InWorldDate (sortable), optional end date
 ├─ location: Page?  (a Place)
 └─ participants: [PageLink role=participant]

WorldMap
 ├─ image (externalStorage), name
 ├─ place: Page?     (the place this map depicts, enabling nested maps)
 └─ MapPin[]         (normalised x/y in 0...1, target Page, optional icon)
```

**Why one `Page` model rather than six.** Linking, search, `@` mentions, hierarchy and CloudKit all work against a single type. Per-kind behaviour comes from `PageKind` plus the attribute schema. A view for a particular kind can still use typed accessors.

**Where `AttributedString` fits.** It is `Codable`. Mentions are stored as a custom `AttributeScope` attribute holding the target page ID. Renaming a page therefore never breaks links, because the display text refreshes from the ID.

## 4. Rule Systems and Attributes (data-driven)

```swift
struct AttributeDefinition: Identifiable {
    let key: String              // stable, e.g. "dnd5e.armorClass"
    let label: String
    let type: AttributeType      // .text, .number, .bool, .choice([..]), .dice, .page(kind), .list
    let appliesTo: Set<PageKind>
    let group: String            // section heading in the editor
}

protocol RuleSystem {
    var id: RuleSystemID { get }
    var name: String { get }
    var attributes: [AttributeDefinition] { get }
}
```

- A **core** set of attributes always applies to each kind (for example a Place's population or an Item's rarity-neutral description).
- `DnD5eSystem` adds attributes such as AC, HP, CR, ability scores, alignment, size, creature type, item rarity and attunement.
- The editor builds its forms from definitions, so adding a system means adding a file and no new UI.
- Values are stored by stable key. Switching or removing a system never deletes data. Unused attributes are hidden and kept.
- The SRD content is open, but v1 ships attribute definitions only, with no copyrighted text.

## 5. Features

### 5.1 Pages and editing
- A sidebar of kinds, a list per kind, and a detail editor.
- The editor has a header (title, summary, kind badge), grouped attribute sections, and a rich-text body.
- Typing `@` opens a search popover. Selecting a result inserts a mention run and creates or updates a `PageLink`.
- A **Backlinks** section lists everything that references this page.

### 5.2 Place hierarchy
- Places have a `parent`, with a place type (region, settlement, building, wilderness, point of interest and so on).
- The UI shows a tree (outline) and breadcrumbs.
- Cycles are prevented.

### 5.3 Maps
- Import an image with `PhotosPicker` or `fileImporter`.
- Render in a zoomable, pannable view. Use `ScrollView` with magnification on iOS and a native-feeling gesture setup on macOS.
- Tap to add a pin, then pick or create a Place. Pins are stored in normalised coordinates, so image resolution doesn't matter.
- A place can have its own map, so a pin can drill down (region map to town map).
- Very large images are downsampled for display with ImageIO, and the original is kept.

### 5.4 Events, timelines and movement
- Events carry an in-world date, a location and participants.
- The **timeline** view sorts a world's events, with filters (campaign or backstory, character, place, organisation).
- The **character journey** is derived. For a character, take the events they participated in, order them by date, and read each event's location. That gives an ordered list of places.
- Journey display is a list and timeline first. A path overlaid on a map comes later, using pins for the places.
- Nothing is stored for movement. It is always computed from events, so it can't go stale.

### 5.5 Search
- **v1:** a SwiftData predicate search over title, summary, tags and body text, with a kind filter. The same query backs the `@` picker.
- **Later:** Core Spotlight indexing, and `searchable` scopes by kind.

## 6. Architecture and Layout

```
encounter/
  App/            encounterApp, root navigation, ModelContainer setup
  Models/         World, Campaign, Page, PageLink, WorldMap, MapPin, InWorldDate
  Systems/        RuleSystem, AttributeDefinition, Core, DnD5e
  Features/
    Pages/        list, detail, editor, attribute form
    Mentions/     AttributedString scope, @ picker, link syncing
    Places/       hierarchy tree, breadcrumbs
    Maps/         importer, viewer, pins
    Timeline/     event timeline, character journey
    Search/
  Shared/         components, extensions
encounterTests/   Swift Testing: models, link syncing, journey derivation, search
```

SwiftUI views read from `@Query` and `@Environment(\.modelContext)`. Logic that is more than trivial (link syncing, journey derivation, hierarchy validation) lives in plain Swift types that are unit-testable without UI.

## 7. Milestones

Each milestone ends with a building app and passing tests. I'll stop and show you the result before the next one.

| # | Milestone | Outcome |
|---|---|---|
| 0 | **Foundation** | Remove template `Item`. Set up the models, the container, a world list and picker, an empty split-view shell and a sample-data preview. |
| 1 | **Pages and attributes** | Create, edit and delete pages of every kind. Core attribute forms. Playable / non-playable for characters. |
| 2 | **Images** | Multiple images per page, a default image, thumbnails in lists. |
| 3 | **Rule systems** | The system picker per World. D&D 5e attributes appear for the relevant kinds. |
| 4 | **JSON import / export** | Versioned format for a whole world (including images and maps). Used to create the first test data. |
| 5 | **Links and mentions** | `@` mentions, `PageLink`s, backlinks. |
| 6 | **Place hierarchy** | Parenting, outline, breadcrumbs. |
| 7 | **Search** | Global search and kind filters. |
| 8 | **Calendars** | Custom calendar editor per world, `InWorldDate` entry and formatting. |
| 9 | **Maps** | Import, view, pins, nested maps. |
| 10 | **Events and timelines** | Event fields, campaign vs backstory, timeline view, character journey. |
| 11 | **Polish** | Keyboard shortcuts and menus on Mac, iPad multitasking, accessibility audit (Dynamic Type, VoiceOver, contrast), empty states. |
| 12 | **CloudKit** (when a developer account exists) | Capability, container, conflict testing on multiple devices. |

Search comes before maps because the `@` picker needs it. Import/export comes early so every later feature can be tested against realistic data, and the export format grows with each milestone (maps, events and so on).

### JSON format notes
- Top-level `formatVersion`, so older files can still be read.
- Records reference each other by stable UUIDs, so links, hierarchy and pins survive a round trip.
- Worlds are exported as a package (`.encounterworld`, a directory with `world.json` and `images/`) so files stay small and readable. It will be declared as a document package type.
- Import creates a new world by default and never overwrites an existing one silently.
- Round-trip tests (export, import, compare) are required for every model added.

## 8. Working Agreement (proposed behaviours)

Please edit anything here that doesn't suit you.

**Scope and process**
1. I build one milestone at a time and keep changes limited to it. I won't refactor unrelated code.
2. Before starting each milestone I post a short plan (files to add or change, key decisions). Then I build.
3. If a requirement is ambiguous, or a choice affects the data model, I ask first. Otherwise I pick the conventional option and tell you.
4. This file is the source of truth. If we change direction, I update it in the same change.

**Code**
5. Swift and SwiftUI only. Apple frameworks only, with no third-party dependencies unless you approve one.
6. async/await and `@Observable`, with no Combine. Follow the project style: PascalCase types, camelCase members, 4-space indent, no force unwraps, comments only for non-obvious logic.
7. I check the current Apple documentation for newer APIs (SwiftData, SwiftUI, AttributedString, MapKit-free image maps) rather than relying on memory.
8. Every model change keeps the CloudKit-compatible rules in section 2.

**Verification**
9. I build after each meaningful change and fix errors before reporting back. I never report something as working without building it.
10. Pure logic gets Swift Testing tests, and I run them. UI is checked with previews and, where practical, a run on a simulator or Mac. If I couldn't verify something, I say so.
11. Reported results are honest: failing tests, skipped steps and known gaps are stated plainly.

**Git and safety**
12. I only commit when you ask. I work on a feature branch, not `main`.
13. I ask before deleting files, changing project or signing settings, or adding capabilities and entitlements.
14. No CloudKit or iCloud capability until you say the developer account is ready.

## 9. Decisions Made

1. **Minimum OS:** 26 and later on all platforms.
2. **Worlds:** the top-level container. A creator can have several, each with one rule system.
3. **Dates:** custom in-world calendars in v1. The creator sets hours per day, the number of months, days per month (editable per month) and month names. Years are fixed length, with no leap rules.
4. **Characters:** playable, NPCs and monsters share one form and attribute set. A playable / non-playable flag distinguishes them, so playable characters can get extra attributes later. Monsters and friendly animals are non-playable characters, told apart by a creature type attribute only, with no separate filter.
5. **Images:** pages hold multiple images, one of which is the default.
6. **Import/export:** JSON, also used to create initial test data. The format is a `.encounterworld` package (a folder holding `world.json` and `images/`).

## 10. Open Questions

None at the moment.
