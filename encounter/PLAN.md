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
10. A shared, read-only D&D 5e content library (races and their traits, classes and their features), in both SRD editions, that creators can base their own custom types on.
11. A guided character builder that creates a playable character from that content, starting at level 1 and then supporting higher levels.

**Non-goals for v1:** CloudKit sync, sharing or collaboration, player and DM visibility controls, other TTRPG systems, other import/export formats (Markdown, VTT), a combat tracker.

## 2. Technical Decisions

| Area | Decision | Reason |
|---|---|---|
| UI | SwiftUI only. `NavigationSplitView` is the shell and adapts to Mac, iPad and iPhone. | One codebase, native behaviour on each platform. |
| Persistence | SwiftData, with a CloudKit-compatible schema from day one. | CloudKit can be enabled later with no migration pain. |
| Concurrency | async/await and `@Observable`. No Combine. | Project guideline. |
| Tests | Swift Testing for unit tests, XCUIAutomation for UI tests. | Project guideline. |
| Targets | One multiplatform app target. Minimum OS is 27 on iOS, iPadOS and macOS. | Gives `TextEditor` with `AttributedString`, drag-to-reorder (`reorderable()`) and current SwiftUI APIs. |

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
- Until the D&D content milestone, the app ships attribute definitions only, with no rules text. Bundled content (section 5.6) is limited to openly licensed SRD material.
- **Built so far:** the `RuleSystem` protocol, the `RuleSystems` registry, `NoRuleSystem` and `DnD5eSystem`. A system can override a core attribute by reusing its key (D&D turns Creature Type, Item Type and a race's Size into pickers). The field types are text, number, bool, ability score (shown with its modifier), choice and page reference.

## 5. Features

### 5.1 Pages and editing
- A sidebar of kinds, a list per kind, and a detail editor.
- The editor has a header (title, summary, kind badge), grouped attribute sections, and a rich-text body.
- Typing `@` opens a search popover. Selecting a result inserts a mention run and creates or updates a `PageLink`.
- A **Backlinks** section lists everything that references this page.

### 5.1a World home page
- Each world has a **Home** entry at the top of its sidebar, selected when the world opens. Its page holds the world's name, a free-text summary, the rule system picker, and the world's own images (several, with a default, same as pages).
- Export and Delete are on the home page, and are the only places to do them. The worlds list is for opening, creating and importing, with no context menu or swipe actions.
- The window is two columns, sidebar and detail, so the home page uses the whole width beside the sidebar. For a page kind, the detail area holds the page list and the editor side by side (a split view on the Mac, a nested split view on iPad and iPhone). SwiftUI can't hide only the middle column of a three-column split, which is why the structure changed.
- Deleting a world leaves its screens first and deletes afterwards, so nothing is ever showing a deleted world.
- Images are shared code: pages and worlds both conform to `ImageOwner`, which holds the default-image, ordering and removal rules. World images are exported and imported with the world (an optional field, so older files still read).

### 5.1b Mentions and backlinks (as built, milestone 5)
- **Storage:** a mention is a standard link run in the notes pointing at `encounter://page/<page id>`. A custom text attribute was ruled out because it doesn't survive being saved or exported with the default coders. Tests check that links survive SwiftData and the JSON coder.
- **Typing:** `@` at the start of the text or after whitespace or `(` opens suggestions for pages in the same world. The query may contain spaces and stops at a line break or after 40 characters, so email addresses and stray `@`s don't trigger it. Choosing a page replaces `@query` with a mention and a trailing unlinked space, and puts the cursor after it. (SwiftUI otherwise leaves the inserted text selected, so the next key would replace the mention.) A **Mention Page…** button does the same for touch devices.
- **Links:** `MentionSync` keeps one `PageLink` with the role "mention" per distinct page mentioned. Mention links are derived from the text, so they are not exported, and import rebuilds them. Other roles are never touched.
- **Maintenance:** renaming a page updates the text of mentions of it (a blank title is ignored). Deleting a page turns mentions of it into plain text first.
- **Import:** mention URLs are remapped to the new page IDs, and a mention of a page that isn't in the file becomes plain text.
- **Navigation:** `WorldNavigation` holds the sidebar selection and open page, shared through the environment, so a mention or a Referenced By row can open a page of any kind.
- **Referenced By:** lists mentions and structured links (race, location, participant and so on), each described from the target's side ("Has this race", "Happened here").
- **Mentions as blocks:** the editor treats a link as ordinary text, so `Mention.normalize` corrects the notes after every edit. Deleting any part of a mention deletes all of it, text typed against a mention loses the link, and text typed inside one turns it into plain text. A mention whose text has gone stale is left alone unless it is edited.
- **Clicking a mention:** `TextEditor` hands link clicks to the system, not to the app, which showed "no application set to open the URL". So the app registers the `encounter://` scheme in `Info.plist`, receives the URL with `onOpenURL`, and `LinkRouter` opens the page in the world that is showing. `handlesExternalEvents` keeps the existing window from being duplicated. With several windows open, the world shown last receives links. macOS learns a new URL scheme at launch, and may send links to an older build of the app if several exist.
- **Known limit:** the suggestion list appears under the notes, not at the cursor, because the editor doesn't expose the cursor position.

### 5.2 Place hierarchy
- Places have a `parent`, with a place type (region, settlement, building, wilderness, point of interest and so on).
- **Outline and breadcrumbs (8a, built):** the Places list is an outline that opens down to the selected place. A place page shows breadcrumbs (each opens that place), a **Located In** picker, the places inside it and **Add Place Here**. Cycles are prevented: the picker leaves out the place itself and what is inside it. Deleting a place moves its contents up a level.
- **World coordinates (8b, built):** places get real positions on a flat plane of metres, like the UK National Grid: **eastings** (x, east) and **northings** (y, north) from a south-west origin, both non-negative. Users never see raw numbers. A place's `geometry` is a point (a tavern) or a polygon footprint (a settlement or region). It is stored on the page as encoded JSON, because SwiftData lost a polygon's corners when it stored the enum directly (a test caught this). Maps (milestone 11) will set positions, by drawing polygons and dropping pins on a map calibrated in metres. Until then they are set in code and tests only.
- **Spatial logic:** a pure `PlaceGeometry` calculator: validity (on the plane, a polygon needs three corners, an area and no self-crossing), area, centre, distance, point in polygon (edges count as inside) and polygon in polygon (smaller, all inside, no edge crossing out, so concave outlines work).
- **Automatic parents:** `setGeometry` refreshes the world. A place with a position and no parent chosen by the creator gets the smallest place around it as its parent. `parentSource` records who chose a parent: `automatic` (may be recalculated) or `manual` (never replaced, and choosing "Nowhere" counts as a choice). A parent with no recorded source is treated as manual. Removing a position, or the outline around it, removes an automatic parent.
- **Export and import:** `geometry` and `parentSource` are optional fields on a page record, so the format version stays 1 and older files still import. An invalid shape in a file is dropped.

### 5.3 Maps
- Import an image with `PhotosPicker` or `fileImporter`.
- Render in a zoomable, pannable view. Use `ScrollView` with magnification on iOS and a native-feeling gesture setup on macOS.
- Tap to add a pin, then pick or create a Place. Pins are stored in normalised coordinates, so image resolution doesn't matter.
- A place can have its own map, so a pin can drill down (region map to town map).
- Very large images are downsampled for display with ImageIO, and the original is kept.

- **Calibrated maps (milestone 11):** a map gets a calibration from pixels to metres (an origin, a scale and a rotation, set by marking two known points). Drawing a polygon or dropping a pin then writes `Page.geometry`, and automatic parents follow. A place appears on every map that covers it, and nesting between maps comes from their areas, so nothing is pinned twice.
- **Pins are derived:** with a calibrated map, a pin just points at a place and is drawn from `place.geometry`. Pins on an uncalibrated map keep their own normalised image position. `MapPin` isn't used by any screen yet, so changing it is cheap.
- **Limit:** a world has one plane. Building floors, dungeon levels and other planes would overlap on it, and will need their own plane (a "space" a place belongs to) or a height value later. The geometry maths wouldn't change.

### 5.4 Events, timelines and movement
- Events carry an in-world date, a location and participants.
- The **timeline** view sorts a world's events, with filters (campaign or backstory, character, place, organisation).
- The **character journey** is derived. For a character, take the events they participated in, order them by date, and read each event's location. That gives an ordered list of places.
- Journey display is a list and timeline first. A path overlaid on a map comes later, using pins for the places.
- Nothing is stored for movement. It is always computed from events, so it can't go stale.

### 5.5 Search
- **v1:** a SwiftData predicate search over title, summary, tags and body text, with a kind filter. The same query backs the `@` picker.
- **Later:** Core Spotlight indexing, and `searchable` scopes by kind.

### 5.6 D&D 5e content library

Races or species with their traits, and classes with their features, shipped with the app as a shared library.

- **Shared and read-only:** the library is bundled with the app and is not stored in any world. Every world sees the same entries, so a content update reaches all worlds, and CloudKit never has to sync it. Library entries can't be edited.
- **Custom versions:** from any library entry, **Create Custom Version** makes an ordinary, editable page in the current world (a homebrew variant). The copy remembers which library entry it came from (`basedOnKey`).
- **Editions:** the open SRD exists as 5.1 (2014 rules) and 5.2 (2024 rules), and both are bundled. Each **world** chooses its edition (a setting on the world, next to its rule system), and the library shows that edition's content. In 5.2 the interface says "Species" instead of "Race".
- **Content format:** bundled JSON content packs, one per edition, with stable keys such as `srd51.race.elf`. Packs use the same record format as world export (section 7), so there is one parser.
- **Library entries:** a name, summary, attributes (size, speed, hit die and so on) and structured **entries** (see below), plus the source and attribution.
- **Races and species:** size, speed, darkvision, languages and a list of traits. Subraces refer to their parent.
- **Classes:** a new page kind, **Class**, with hit die, primary ability, saving throw proficiencies, armor and weapon proficiencies, spellcasting ability, and features by level. Subclasses refer to their class.
- **More kinds (milestones 7a to 7d):** skills, backgrounds, feats, equipment and spells, in both editions. The SRDs hold one background in 5.1 and four in 5.2.1, so most backgrounds are creators' own pages. They are read the same way as library ones.
- **Structured entries:** traits and class features are lists of entries (name, description and, for classes, level). `AttributeValue` gains an entries case, and the page editor gains a list editor for it.
- **Browsing:** a **Library** section in the sidebar lists library entries read-only, with the Create Custom Version button. Library entries also appear in search and in the pickers below.
- **Referencing library content:** a character's race and class can each be a world page or a library entry. Pickers show both, grouped as "This World" and "Library". A world page is stored as a `PageLink`. A library entry is stored by key, in an attribute such as `core.raceLibraryKey`. Exactly one of the two is set.
- **Missing keys:** a reference to a key the installed library doesn't contain (a newer export opened in an older app) shows as "Unavailable library entry" and loses nothing.
- **Export and import:** a world export stores library references as keys, not as content, so exports stay small. Custom versions export as ordinary pages.
- **Class category visibility:** the Classes category shows in the sidebar when the world's rule system has classes, or when the world already contains class pages. So worlds on "None" don't see an empty Classes category, and switching systems never hides existing pages.
- **Characters:** a character has a class reference and a Class Level, next to its race. Playable and non-playable characters still share one form.
- **Licensing:** only openly licensed SRD content is bundled, with the required attribution shown in the app (an About screen) and stored inside each pack. Anything outside the SRD isn't shipped. Creators can write their own pages and custom versions.

**Licensing, verified against the official PDFs.** Both SRDs are under CC-BY-4.0, and each requires its own attribution statement in the work. These are the exact statements on page 1 of each document. Wizards asks that no other attribution to Wizards be added, and CC-BY-4.0 requires saying if the material was changed.

- SRD 5.1: *This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.*
- SRD 5.2.1: *This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode.*
- 5.2.1 is the current version of the 2024-rules SRD (corrections to 5.2), so that is the one bundled.
- The app shows the matching statement on every library screen and on an About screen, and each pack carries it. A note says the text was reformatted for display and that its wording is unchanged.

**Sourcing the content.** Rules text is taken from the official PDFs by a converter tool, never typed from memory, so the wording is exact. The tool lives in the repository (like the sample world generator), strips page furniture and whitespace artefacts, and writes the packs. Each pack is checked: every expected race or class is present, class features carry the right levels (cross-checked against each class's progression table), and no text is cut off.

**Content pack format (draft).** One JSON file per edition, bundled in the app:

```json
{
  "formatVersion": 1,
  "id": "srd51",
  "name": "SRD 5.1",
  "edition": "5.1 (2014 rules)",
  "raceTerm": "Race",
  "attribution": "<the statement above>",
  "entries": [
    {
      "key": "srd51.race.elf",
      "kind": "race",
      "name": "Elf",
      "parent": null,
      "summary": "Short description.",
      "attributes": { "core.raceSize": "Medium", "dnd5e.speed": "30 ft.", "dnd5e.darkvision": "60 ft." },
      "entries": [ { "name": "Keen Senses", "level": null, "text": "You have proficiency in the Perception skill." } ]
    },
    {
      "key": "srd51.class.fighter",
      "kind": "class",
      "name": "Fighter",
      "attributes": { "dnd5e.hitDie": "d10", "dnd5e.savingThrows": ["Strength", "Constitution"] },
      "entries": [ { "name": "Second Wind", "level": 1, "text": "…" } ]
    },
    { "key": "srd51.subclass.champion", "kind": "subclass", "name": "Champion", "parent": "srd51.class.fighter", "entries": [ … ] }
  ]
}
```

- Keys are permanent. They are never reused or renamed, because worlds refer to library entries by key.
- `kind` is `race` (species in 5.2.1), `class` or `subclass`. A subclass names its class in `parent`, and a subrace names its race.
- `attributes` use the same keys as page attributes, so a custom version is a plain copy.
- `entries` are the structured traits and features: a name, an optional level and the text.

### 5.7 Character builder

A guided flow that produces a playable character page.

1. **Name and concept:** name, alignment, optional portrait.
2. **Race or species:** pick from the library or the world's own pages, and from subraces where there are any. Traits and ability bonuses are shown.
3. **Class:** pick from the library or the world's own pages, with a summary of the features for the chosen level.
4. **Ability scores:** standard array, point buy, or manual entry. Rolling in the app can come later. Racial bonuses are applied and the modifiers shown.
5. **Review:** a summary with derived values such as proficiency bonus, hit points and armor class (10 plus Dexterity modifier, until equipment exists).
6. **Create:** makes a playable character page with its race and class references and all attributes filled in. The creator can then edit it like any other page.

- Derivations live in plain Swift types (a `CharacterDraft` plus calculators) so they're unit-tested without UI.
- The builder reads the library and the world's own pages together, so homebrew races and classes work the same as bundled ones.
- **Level 1 first:** milestone 7e builds level 1, including **skills, equipment, spells and backgrounds**, so those are added to the library first (milestones 7a to 7d).
- **Editions differ:** in 5.1, ability score bonuses, languages and some proficiencies come from the race. In 5.2.1 the ability score bonuses, two skills, a tool and an origin feat come from the background, and species have none.
- **Few backgrounds in the SRD:** the 5.1 SRD has one background (Acolyte) and 5.2.1 has four. The builder treats library and world backgrounds alike, so creators add their own as pages, starting from Create Custom Version.
- **Higher levels soon after:** a later milestone (13, after events and timelines) adds levelling up to a character page: choosing the new level, applying hit points, proficiency bonus changes and the class features gained, with subclass choice where the class requires it.

## 6. Architecture and Layout

```
encounter/
  App/            encounterApp, root navigation, ModelContainer setup
  Models/         World, Campaign, Page, PageLink, WorldMap, MapPin, InWorldDate
  Systems/        RuleSystem, AttributeDefinition, Core, DnD5e
  Content/        bundled read-only content packs (SRD 5.1 and 5.2 races, classes), loader, attribution
  Features/
    Pages/        list, detail, editor, attribute form
    Mentions/     AttributedString scope, @ picker, link syncing
    Places/       hierarchy tree, breadcrumbs
    Maps/         importer, viewer, pins
    Timeline/     event timeline, character journey
    Library/      read-only library browser, Create Custom Version
    CharacterBuilder/  guided flow, draft, calculators, levelling up
    Search/
  Shared/         components, extensions
encounterTests/   Swift Testing: models, link syncing, journey derivation, search
```

SwiftUI views read from `@Query` and `@Environment(\.modelContext)`. Logic that is more than trivial (link syncing, journey derivation, hierarchy validation) lives in plain Swift types that are unit-testable without UI.

## 7. Milestones

Each milestone ends with a building app and passing tests. I'll stop and show you the result before the next one.

| # | Milestone | Status | Outcome |
|---|---|---|---|
| 0 | **Foundation** | Done | Remove template `Item`. Set up the models, the container, a world list and picker, an empty split-view shell and a sample-data preview. |
| 1 | **Pages and attributes** | Done | Create, edit and delete pages of every kind. Core attribute forms. Playable / non-playable for characters. Race picker on characters. |
| 2 | **Images** | Done | Multiple images per page, a default image, thumbnails in lists, drag to reorder, drag in from Finder. |
| 3 | **Rule systems** | Done | The system picker per World. D&D 5e attributes appear for the relevant kinds, including ability score modifiers. |
| 4 | **JSON import / export** | Done | Versioned `.encounterworld` package for a whole world (including images and maps), Import World and Export in the world list, and a sample world (`Samples/Saltmarch Coast.encounterworld`) for test data. |
| 5 | **Links and mentions** | Done | `@` mentions in notes, kept in step with `PageLink`s, a Referenced By section, tappable mentions, and navigation between pages of any kind. |
| 6a | **D&D library: foundations** | Built, awaiting review | Content pack format and loader, structured trait and feature entries (and their editor), Class page kind (shown when relevant), per-world edition setting, Library section in the sidebar, read-only library browser, Create Custom Version (`basedOnKey`), race and class references that can be library or world entries, Class Level on characters, attribution screen. Proven with a small set of entries taken verbatim from the real SRDs (Dwarf, Hill Dwarf, Fighter in 5.1; Dwarf, Fighter in 5.2.1), checked by `Tools/srd/verify.sh`. 181 tests pass. |
| 6b | **D&D library: SRD 5.1 content** | Built, awaiting review | A converter tool that reads the official SRD 5.1 PDF and writes the content pack, then all races (with subraces) and all 12 classes (with their subclass and every feature by level). Includes a checks report for you to review. |
| 6c | **D&D library: SRD 5.2.1 content** | Built, awaiting review | The same for the official SRD 5.2.1: all 9 species and all 12 classes. |
| 7a | **D&D library: new kinds and skills** | Built, awaiting review | The pack format and library browser gain **skills**, **backgrounds**, **feats**, **equipment** and **spells** as kinds (each with its own sidebar list, `@` mentions and Create Custom Version). The 18 skills, with their abilities, for both editions. |
| 7b | **D&D library: backgrounds and feats** | Built, awaiting review | Converter support, then the SRD 5.1 background (Acolyte only) and the SRD 5.2.1 backgrounds (Acolyte, Criminal, Sage, Soldier) and feats, including the origin feats backgrounds grant. Includes a checks report. |
| 7c | **D&D library: equipment** | Built, awaiting review | Weapons, armor, tools, adventuring gear and packs with cost, weight and properties, for both editions, plus the starting equipment choices for each class and background. |
| 7d | **D&D library: spells** | Built, awaiting review | Every SRD spell for both editions (level, school, casting time, range, components, duration, text) and each class's spell list. |
| 7e | **Character builder (level 1)** | Built, awaiting review | Guided flow (name, race or species, class, background, ability scores, skills, equipment, spells, review) that creates a level 1 playable character page. The 5.1 species bonuses come from the race, and the 5.2.1 ones from the background. |
| 8a | **Place hierarchy** | Built, awaiting review | Parenting, outline, breadcrumbs, children, safe deletion. |
| 8b | **Place coordinates** | Built, awaiting review | Metre-based positions and polygons, spatial maths, automatic parents. |
| 9 | **Search** | Planned | Global search and kind filters, including library entries. |
| 10 | **Calendars** | Planned | Custom calendar editor per world, `InWorldDate` entry and formatting. |
| 11 | **Maps** | Planned | Import, view, pins, nested maps. |
| 12 | **Events and timelines** | Planned | Event fields, campaign vs backstory, timeline view, character journey. |
| 13 | **Character levelling** | Planned (deferred until after events and timelines) | Level a character up to 20: hit points, proficiency bonus, class features gained, subclass choice, and new spells. |
| 14 | **Polish** | Planned | Keyboard shortcuts and menus on Mac, iPad multitasking, accessibility audit (Dynamic Type, VoiceOver, contrast), empty states. |
| 15 | **CloudKit** (when a developer account exists) | Planned | Capability, container, conflict testing on multiple devices. The library is bundled and is not synced. |

Search comes before maps because the `@` picker needs it. Import/export comes early so every later feature can be tested against realistic data, and the export format grows with each milestone (maps, events and so on). The D&D content library follows import/export and links because content packs reuse the import format and a character cross-references its race and class. The character builder follows the library because it reads those entries, which now include skills, backgrounds, feats, equipment and spells (7a to 7d), and levelling follows the builder. Library entries should join search when search is built, so the search milestone (9) covers them.

### JSON format notes
- Top-level `formatVersion`, so older files can still be read.
- Records reference each other by stable UUIDs, so links, hierarchy and pins survive a round trip.
- Worlds are exported as a package (`.encounterworld`, a directory with `world.json` and `images/`) so files stay small and readable. It will be declared as a document package type.
- Import creates a new world by default and never overwrites an existing one silently.
- Round-trip tests (export, import, compare) are required for every model added.

**As built (milestone 4):**
- `world.json` holds plain `Codable` records (`WorldArchive` and friends), separate from the SwiftData models. `formatVersion` is 1. Fields added later should be optional so older files still decode, and a file with a newer version is refused with a clear message.
- Page notes keep their formatting. Thumbnails aren't exported, and are regenerated on import.
- Imports always create a new world, with fresh IDs for every record. A name clash gets a suffix ("Name (2)"). A link to a missing page, or an image that is missing or can't be decoded, is skipped and counted in the summary the user sees.
- Imports repair a parent loop in a file, and a missing or duplicated default image.
- The `.encounterworld` type is declared as an exported type in the app's Info.plist (conforming to `com.apple.package`), and the app's sandbox can read and write files the user picks.
- Library references (milestone 6) will be stored as keys, not content.
- `Samples/make-sample-world/` regenerates the sample world. It is compiled against the app's own format types and checks its own output, so the sample can't drift from the format.

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

1. **Minimum OS:** 27 and later on all platforms (raised from 26 to use SwiftUI's drag-to-reorder).
2. **Worlds:** the top-level container. A creator can have several, each with one rule system.
3. **Dates:** custom in-world calendars in v1. The creator sets hours per day, the number of months, days per month (editable per month) and month names. Years are fixed length, with no leap rules.
4. **Characters:** playable, NPCs and monsters share one form and attribute set. A playable / non-playable flag distinguishes them, so playable characters can get extra attributes later. Monsters and friendly animals are non-playable characters, told apart by a creature type attribute only, with no separate filter.
5. **Images:** pages hold multiple images, one of which is the default.
6. **Import/export:** JSON, also used to create initial test data. The format is a `.encounterworld` package (a folder holding `world.json` and `images/`).

7. **D&D content and character builder:** both are in scope for v1 (sections 5.6 and 5.7, milestones 6 to 8, with 7a to 7e building the library kinds and then the builder).
8. **Editions:** both SRD editions (5.1 and 5.2) are bundled, and each world chooses which one it uses.
9. **Content delivery:** a shared, read-only library bundled with the app. Creators can make editable custom versions of any entry in their own world.
10. **Class kind:** Class is a new page kind. Its sidebar category shows when the world's rule system has classes or the world already has class pages. (My recommended default. It only affects what the sidebar shows, so it's easy to change.)
11. **Traits and features:** structured entries (name, description, level) on the page or library entry, not separate pages.
12. **Builder scope:** level 1 first (milestone 7e), including skills, equipment, spells and backgrounds, which need those kinds in the library first (7a to 7d). Levels 2 to 20 follow in milestone 8.

## 10. Open Questions

None blocking. Before milestone 6 I'll check the exact SRD 5.1 and 5.2 licence and attribution wording, and I'll post the milestone plan with the content pack format for review.
