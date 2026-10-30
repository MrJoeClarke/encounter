// Generates Samples/Saltmarch Coast.encounterworld, a small original D&D 5e world for trying the app and for test data.
//
// It is compiled against the app's own file-format types, so the sample can't drift from the real format.
// Run it from the repository root with Samples/make-sample-world/build.sh.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Images

func jpeg(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> Data {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("No bitmap context") }
    draw(context, CGSize(width: width, height: height))
    let output = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
    else { fatalError("Could not encode image") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: 1)
}

/// A simple abstract portrait: a gradient background with a head-and-shoulders silhouette.
func portrait(top: CGColor, bottom: CGColor, figure: CGColor) -> Data {
    jpeg(width: 400, height: 400) { context, size in
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bottom, top] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        context.setFillColor(figure)
        context.fillEllipse(in: CGRect(x: 140, y: 190, width: 120, height: 130))
        context.fillEllipse(in: CGRect(x: 70, y: -120, width: 260, height: 260))
    }
}

/// A rough coastline map: sea, a landmass and a few lighter shallows.
func coastMap() -> Data {
    jpeg(width: 1200, height: 800) { context, size in
        context.setFillColor(color(0.20, 0.38, 0.55))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(color(0.28, 0.48, 0.64))
        context.fillEllipse(in: CGRect(x: 650, y: 80, width: 480, height: 300))
        let land = CGMutablePath()
        land.move(to: CGPoint(x: 0, y: 800))
        land.addLine(to: CGPoint(x: 0, y: 120))
        land.addCurve(to: CGPoint(x: 380, y: 260), control1: CGPoint(x: 140, y: 80), control2: CGPoint(x: 260, y: 300))
        land.addCurve(to: CGPoint(x: 520, y: 470), control1: CGPoint(x: 460, y: 220), control2: CGPoint(x: 600, y: 360))
        land.addCurve(to: CGPoint(x: 760, y: 600), control1: CGPoint(x: 460, y: 560), control2: CGPoint(x: 640, y: 640))
        land.addCurve(to: CGPoint(x: 1200, y: 640), control1: CGPoint(x: 900, y: 560), control2: CGPoint(x: 1040, y: 700))
        land.addLine(to: CGPoint(x: 1200, y: 800))
        land.closeSubpath()
        context.addPath(land)
        context.setFillColor(color(0.72, 0.66, 0.48))
        context.fillPath()
        // The fen
        context.setFillColor(color(0.45, 0.55, 0.38))
        context.fillEllipse(in: CGRect(x: 150, y: 330, width: 260, height: 200))
    }
}

/// A dusk scene for the world's cover: warm sky, dark sea and a lighthouse on the point.
func coverImage() -> Data {
    jpeg(width: 1200, height: 600) { context, size in
        let sky = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0.95, 0.60, 0.35), color(0.30, 0.20, 0.45)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        context.setFillColor(color(0.08, 0.14, 0.26))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: 200))
        // The point and the lighthouse
        context.setFillColor(color(0.05, 0.07, 0.12))
        context.fillEllipse(in: CGRect(x: 640, y: 120, width: 700, height: 160))
        let tower = CGMutablePath()
        tower.move(to: CGPoint(x: 900, y: 230))
        tower.addLine(to: CGPoint(x: 960, y: 230))
        tower.addLine(to: CGPoint(x: 945, y: 430))
        tower.addLine(to: CGPoint(x: 915, y: 430))
        tower.closeSubpath()
        context.addPath(tower)
        context.fillPath()
        context.fill(CGRect(x: 905, y: 430, width: 50, height: 28))
        context.setFillColor(color(1.0, 0.92, 0.6))
        context.fill(CGRect(x: 920, y: 432, width: 20, height: 22))
    }
}

// MARK: - Records

var files: [String: Data] = [:]

func store(_ data: Data, id: UUID) -> String {
    let name = "\(id.uuidString).jpeg"
    files[name] = data
    return name
}

let names = [
    "Saltmarch Coast", "Brackwater", "The Gilded Gull", "Mistfen", "Old Lighthouse",
    "Human", "Dwarf", "Marshkin",
    "Mira Thorne", "Bram Ironvale", "Captain Odric Vane", "Grishka the Mist-Hag", "Pip",
    "Lantern of the Drowned", "Brackwater Charter",
    "Harbor Guild", "Order of the Pale Lamp",
    "The Founding of Brackwater", "The Great Drowning", "Arrival at Brackwater", "Night at the Lighthouse",
]
let ids: [String: UUID] = Dictionary(uniqueKeysWithValues: names.map { ($0, UUID()) })
func id(_ name: String) -> UUID { ids[name]! }

/// A mention of another page, as the Markdown link the app stores in notes.
func m(_ name: String) -> String { "[\(name)](encounter://page/\(id(name)))" }

let campaignID = UUID()
let base = Date(timeIntervalSince1970: 1_790_000_000)
var order = 0

func text(_ markdown: String) -> AttributedString {
    (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
}

func page(
    _ title: String,
    kind: String,
    summary: String,
    body: String,
    role: String? = nil,
    attributes: [String: AttributeValue] = [:],
    tags: [String] = [],
    parent: String? = nil,
    origin: String? = nil,
    start: InWorldDate? = nil,
    end: InWorldDate? = nil,
    campaign: Bool = false,
    images: [(caption: String, data: Data)] = []
) -> PageRecord {
    order += 1
    let created = base.addingTimeInterval(Double(order) * 60)
    return PageRecord(
        id: id(title), title: title, summary: summary, kind: kind, characterRole: role,
        body: text(body), attributes: attributes, tags: tags, createdAt: created, updatedAt: created,
        eventOrigin: origin, startDate: start, endDate: end,
        campaignID: campaign ? campaignID : nil,
        parentID: parent.map(id),
        images: images.enumerated().map { index, image in
            let imageID = UUID()
            return ImageRecord(id: imageID, caption: image.caption, sortOrder: index, isDefault: index == 0, file: store(image.data, id: imageID))
        }
    )
}

func stats(_ str: Double, _ dex: Double, _ con: Double, _ int: Double, _ wis: Double, _ cha: Double) -> [String: AttributeValue] {
    [
        "dnd5e.strength": .number(str), "dnd5e.dexterity": .number(dex), "dnd5e.constitution": .number(con),
        "dnd5e.intelligence": .number(int), "dnd5e.wisdom": .number(wis), "dnd5e.charisma": .number(cha),
    ]
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> InWorldDate {
    InWorldDate(year: year, month: month, day: day, hour: hour)
}

var pages: [PageRecord] = []

// Places
pages.append(page("Saltmarch Coast", kind: "place",
    summary: "A windswept stretch of coast, fen and fishing towns.",
    body: "The **Saltmarch Coast** runs for two hundred miles between the grey cliffs of the north and the \(m("Mistfen")) in the south. Its largest town is \(m("Brackwater")). Its people live by fishing, salvage and trade, and watch the tide tables more closely than the calendar.",
    attributes: ["core.placeType": .text("Region"), "core.population": .number(48_000)], tags: ["coast"]))
pages.append(page("Brackwater", kind: "place",
    summary: "A busy harbor town built on the ruins of an older one.",
    body: "**Brackwater** is the largest town on the coast. Its lower streets flood at spring tides, and the oldest cellars are said to open into the drowned city beneath. The harbor is run by \(m("Captain Odric Vane")) and the \(m("Harbor Guild")), and every job starts at \(m("The Gilded Gull")).",
    attributes: ["core.placeType": .text("Settlement"), "core.population": .number(6_200)], tags: ["town", "harbor"], parent: "Saltmarch Coast"))
pages.append(page("The Gilded Gull", kind: "place",
    summary: "A dockside tavern where every job on the coast starts.",
    body: "Run by a retired smuggler, the **Gilded Gull** has a stuffed gull above the bar that is, regulars insist, the original owner.",
    attributes: ["core.placeType": .text("Building")], tags: ["tavern"], parent: "Brackwater"))
pages.append(page("Mistfen", kind: "place",
    summary: "A fog-bound fen where paths shift overnight.",
    body: "Travellers cross the **Mistfen** only with a marsh guide. The fog carries sounds in odd directions, and the lights seen at night are not all swamp gas.",
    attributes: ["core.placeType": .text("Wilderness")], tags: ["wilderness", "danger"], parent: "Saltmarch Coast"))
pages.append(page("Old Lighthouse", kind: "place",
    summary: "A dark tower on the point, long abandoned.",
    body: "The **Old Lighthouse** went dark the night of the Great Drowning. Locals say its lamp still turns, though nobody has found the keeper.",
    attributes: ["core.placeType": .text("Point of Interest")], tags: ["ruin", "mystery"], parent: "Saltmarch Coast"))

// Races
pages.append(page("Human", kind: "race",
    summary: "Adaptable and ambitious, found in every harbor.",
    body: "Humans arrived on the coast last, and now run most of its ports.",
    attributes: ["core.raceSize": .text("Medium"), "dnd5e.speed": .text("30 ft."), "dnd5e.languages": .text("Common and one other"), "core.lifespan": .text("About 80 years")]))
pages.append(page("Dwarf", kind: "race",
    summary: "Stout salvage-divers and stonemasons.",
    body: "Coastal dwarves trade the mountain halls of their ancestors for the dive-bells and breakwaters of the harbors.",
    attributes: ["core.raceSize": .text("Medium"), "dnd5e.speed": .text("25 ft."), "dnd5e.darkvision": .text("60 ft."), "dnd5e.languages": .text("Common and Dwarvish"), "core.lifespan": .text("About 350 years")]))
pages.append(page("Marshkin", kind: "race",
    summary: "A homebrew people of the Mistfen, at home in water and fog.",
    body: "**Marshkin** have webbed fingers, pale green eyes and a knack for finding the one safe path through the fen. They keep to themselves, and are wary of the Order of the Pale Lamp.",
    attributes: ["core.raceSize": .text("Medium"), "dnd5e.speed": .text("30 ft., swim 30 ft."), "dnd5e.darkvision": .text("30 ft."), "dnd5e.languages": .text("Common and Marsh-tongue"), "core.lifespan": .text("About 100 years")],
    tags: ["homebrew"]))

// Characters
pages.append(page("Mira Thorne", kind: "character",
    summary: "A ranger who guides travellers through the Mistfen.",
    body: "**Mira** grew up between \(m("Brackwater")) and the \(m("Mistfen")), and knows both. She took the guiding trade when her father vanished in the fog, and has never stopped looking for him. \(m("Pip")) follows her everywhere.",
    role: "playable",
    attributes: ["core.creatureType": .text("Humanoid"), "core.age": .text("27"), "core.occupation": .text("Marsh guide"),
                 "dnd5e.size": .text("Medium"), "dnd5e.alignment": .text("Neutral Good"), "dnd5e.speed": .text("30 ft."),
                 "dnd5e.armorClass": .number(15), "dnd5e.hitPoints": .number(31), "dnd5e.hitDice": .text("4d10")]
        .merging(stats(11, 17, 14, 10, 15, 9)) { $1 },
    tags: ["party", "ranger"],
    images: [("Mira at the fen's edge", portrait(top: color(0.55, 0.75, 0.55), bottom: color(0.15, 0.35, 0.30), figure: color(0.12, 0.2, 0.17))),
             ("Mira at the Gilded Gull", portrait(top: color(0.9, 0.7, 0.4), bottom: color(0.4, 0.2, 0.1), figure: color(0.2, 0.1, 0.05)))]))
pages.append(page("Bram Ironvale", kind: "character",
    summary: "A dwarf cleric who tends the harbor shrine.",
    body: "**Bram** keeps the shrine at the end of the longest pier, and hears confession from sailors who won't tell anyone else. He blames himself for the Great Drowning, though he was not yet born.",
    role: "playable",
    attributes: ["core.creatureType": .text("Humanoid"), "core.age": .text("112"), "core.occupation": .text("Priest"),
                 "dnd5e.size": .text("Medium"), "dnd5e.alignment": .text("Lawful Good"), "dnd5e.speed": .text("25 ft."),
                 "dnd5e.armorClass": .number(18), "dnd5e.hitPoints": .number(38), "dnd5e.hitDice": .text("4d8")]
        .merging(stats(14, 8, 15, 10, 17, 12)) { $1 },
    tags: ["party", "cleric"],
    images: [("Bram at the shrine", portrait(top: color(0.65, 0.7, 0.85), bottom: color(0.2, 0.25, 0.45), figure: color(0.1, 0.12, 0.25)))]))
pages.append(page("Captain Odric Vane", kind: "character",
    summary: "Harbor master of Brackwater, and nobody's fool.",
    body: "**Odric Vane** has run the harbor for thirty years. He knows what every ship carries, which is why he cannot be bribed and rarely needs to be.",
    role: "nonPlayable",
    attributes: ["core.creatureType": .text("Humanoid"), "core.age": .text("58"), "core.occupation": .text("Harbor master"),
                 "dnd5e.size": .text("Medium"), "dnd5e.alignment": .text("Lawful Neutral"),
                 "dnd5e.challengeRating": .text("2"), "dnd5e.armorClass": .number(16), "dnd5e.hitPoints": .number(52)]
        .merging(stats(13, 12, 14, 12, 15, 14)) { $1 },
    tags: ["npc", "ally"],
    images: [("Captain Vane", portrait(top: color(0.8, 0.8, 0.85), bottom: color(0.3, 0.3, 0.4), figure: color(0.15, 0.15, 0.22)))]))
pages.append(page("Grishka the Mist-Hag", kind: "character",
    summary: "A hag who trades in lost things, and lost people.",
    body: "**Grishka** lives deep in the \(m("Mistfen")) and collects whatever the fog takes. She will sell it back, for a price that is never money.",
    role: "nonPlayable",
    attributes: ["core.creatureType": .text("Fey"), "dnd5e.size": .text("Medium"), "dnd5e.alignment": .text("Neutral Evil"),
                 "dnd5e.challengeRating": .text("3"), "dnd5e.armorClass": .number(17), "dnd5e.hitPoints": .number(82)]
        .merging(stats(18, 12, 16, 13, 14, 14)) { $1 },
    tags: ["monster", "villain"],
    images: [("Grishka", portrait(top: color(0.4, 0.55, 0.4), bottom: color(0.05, 0.12, 0.1), figure: color(0.02, 0.05, 0.04)))]))
pages.append(page("Pip", kind: "character",
    summary: "A very smart gull who has adopted Mira.",
    body: "**Pip** steals chips, lands on shoulders and, somehow, always knows when a storm is coming.",
    role: "nonPlayable",
    attributes: ["core.creatureType": .text("Beast"), "dnd5e.size": .text("Tiny"), "dnd5e.alignment": .text("Unaligned"),
                 "dnd5e.challengeRating": .text("0"), "dnd5e.armorClass": .number(11), "dnd5e.hitPoints": .number(3)]
        .merging(stats(2, 13, 8, 2, 12, 5)) { $1 },
    tags: ["animal", "companion"]))

// Items
pages.append(page("Lantern of the Drowned", kind: "item",
    summary: "A storm lantern whose light shows what the sea has taken.",
    body: "Found in the \(m("Old Lighthouse")). When lit, its pale flame shows drowned things in the water within sixty feet.",
    attributes: ["core.itemType": .text("Wondrous Item"), "dnd5e.rarity": .text("Rare"), "dnd5e.requiresAttunement": .bool(true), "core.value": .text("1,500 gp")],
    tags: ["magic", "quest"]))
pages.append(page("Brackwater Charter", kind: "item",
    summary: "The founding charter, kept in the harbor master's office.",
    body: "A sea-stained scroll. Its last clause, which nobody mentions, grants the town to whoever can prove they hold the lighthouse.",
    attributes: ["core.itemType": .text("Document"), "dnd5e.rarity": .text("Common")],
    tags: ["document", "plot"]))

// Organisations
pages.append(page("Harbor Guild", kind: "organisation",
    summary: "The guild that licenses every boat in Brackwater.",
    body: "The **Harbor Guild** sets the fees, keeps the tide tables and quietly decides which captains get the good berths.",
    attributes: ["core.organisationType": .text("Trade guild"), "dnd5e.alignment": .text("Lawful Neutral"), "core.organisationSize": .text("About 200 members")],
    tags: ["guild"]))
pages.append(page("Order of the Pale Lamp", kind: "organisation",
    summary: "A secretive order hunting for the Lighthouse's lost keeper.",
    body: "The **Order of the Pale Lamp** claims to guard the coast against what rose from the Great Drowning. Its methods are less gentle than its name.",
    attributes: ["core.organisationType": .text("Secret order"), "dnd5e.alignment": .text("Lawful Evil"), "core.organisationSize": .text("About 40 members")],
    tags: ["secret", "villain"]))

// Events
pages.append(page("The Founding of Brackwater", kind: "event",
    summary: "Settlers land on the coast and raise the first quay.",
    body: "The first charter was signed on the beach, in the rain, by seven families.",
    tags: ["history"], origin: "backstory", start: date(112, 4, 9, 10)))
pages.append(page("The Great Drowning", kind: "event",
    summary: "The old city sinks in a single night.",
    body: "A storm, a tidal wave and a dark lighthouse. By dawn the lower city was gone, and the survivors built Brackwater on the high ground.",
    tags: ["history", "disaster"], origin: "backstory", start: date(301, 9, 20, 22), end: date(301, 9, 21, 5)))
pages.append(page("Arrival at Brackwater", kind: "event",
    summary: "The party meets at the Gilded Gull and takes a job from Captain Vane.",
    body: "Mira and Bram are hired to find out why the lighthouse lamp turned last night.",
    tags: ["session 1"], origin: "campaign", start: date(342, 3, 5, 18), campaign: true))
pages.append(page("Night at the Lighthouse", kind: "event",
    summary: "The party reaches the Old Lighthouse and finds the lantern.",
    body: "The lamp is cold, the keeper's room is untouched and the Lantern of the Drowned is waiting on the table.",
    tags: ["session 2"], origin: "campaign", start: date(342, 3, 7, 23), end: date(342, 3, 8, 4), campaign: true))

// Links
var links: [LinkRecord] = []
func link(_ source: String, _ role: String, _ target: String) {
    links.append(LinkRecord(id: UUID(), role: role, sourceID: id(source), targetID: id(target)))
}
link("Mira Thorne", "race", "Human")
link("Bram Ironvale", "race", "Dwarf")
link("Captain Odric Vane", "race", "Human")
link("Grishka the Mist-Hag", "home", "Mistfen")
link("Captain Odric Vane", "member", "Harbor Guild")
link("Bram Ironvale", "home", "Brackwater")
link("Arrival at Brackwater", "location", "The Gilded Gull")
link("Arrival at Brackwater", "participant", "Mira Thorne")
link("Arrival at Brackwater", "participant", "Bram Ironvale")
link("Arrival at Brackwater", "participant", "Captain Odric Vane")
link("Night at the Lighthouse", "location", "Old Lighthouse")
link("Night at the Lighthouse", "participant", "Mira Thorne")
link("Night at the Lighthouse", "participant", "Bram Ironvale")
link("The Great Drowning", "location", "Brackwater")
link("The Founding of Brackwater", "location", "Brackwater")

// Map
let mapID = UUID()
let map = MapRecord(
    id: mapID, name: "The Saltmarch Coast", imageFile: store(coastMap(), id: mapID), placeID: id("Saltmarch Coast"),
    pins: [
        PinRecord(id: UUID(), x: 0.46, y: 0.42, targetID: id("Brackwater")),
        PinRecord(id: UUID(), x: 0.22, y: 0.48, targetID: id("Mistfen")),
        PinRecord(id: UUID(), x: 0.66, y: 0.24, targetID: id("Old Lighthouse")),
    ]
)

// MARK: - Archive

let months: [(String, Int)] = [
    ("Frostwane", 36), ("Thawmoot", 34), ("Seedfall", 36), ("Greenreach", 38), ("Highsun", 36),
    ("Emberturn", 36), ("Harvestide", 34), ("Leaffall", 36), ("Duskwane", 36), ("Deepwinter", 38),
]

let coverID = UUID()
let worldImages = [
    ImageRecord(id: coverID, caption: "The Old Lighthouse at dusk", sortOrder: 0, isDefault: true, file: store(coverImage(), id: coverID)),
]

let archive = WorldArchive(
    exportedAt: base,
    world: WorldRecord(
        id: UUID(), name: "Saltmarch Coast",
        summary: "An original sample world: a foggy coast, a drowned city and a lighthouse that went dark. Made for trying out Encounter.",
        system: "dnd5e", createdAt: base,
        calendar: CalendarRecord(
            hoursPerDay: 24,
            months: months.map { MonthRecord(name: $0.0, dayCount: $0.1) },
            weekdays: ["Moonday", "Tideday", "Windday", "Hearthday", "Starday", "Restday"]
        ),
        images: worldImages
    ),
    campaigns: [CampaignRecord(id: campaignID, name: "Tides of Brackwater", summary: "A low-level mystery campaign on the Saltmarch Coast.", createdAt: base)],
    pages: pages, links: links, maps: [map]
)

// MARK: - Write and verify

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Saltmarch Coast.encounterworld")
try? FileManager.default.removeItem(at: output)
try WorldPackage.fileWrapper(for: WorldPackageContents(archive: archive, files: files))
    .write(to: output, options: .atomic, originalContentsURL: nil)

// Read it back through the real reader and check that everything it refers to exists.
let readBack = try WorldPackage.contents(of: FileWrapper(url: output))
let pageIDs = Set(readBack.archive.pages.map(\.id))
var problems: [String] = []
for page in readBack.archive.pages {
    if let parent = page.parentID, !pageIDs.contains(parent) { problems.append("\(page.title): missing parent") }
    if let campaign = page.campaignID, !readBack.archive.campaigns.contains(where: { $0.id == campaign }) { problems.append("\(page.title): missing campaign") }
    for image in page.images where image.file.map({ readBack.files[$0] == nil }) ?? true { problems.append("\(page.title): missing image file") }
    if !page.images.isEmpty, page.images.filter(\.isDefault).count != 1 { problems.append("\(page.title): needs exactly one default image") }
}
for link in readBack.archive.links where !pageIDs.contains(link.sourceID) || !pageIDs.contains(link.targetID) { problems.append("link \(link.role): dangling") }
for image in readBack.archive.world.images ?? [] where image.file.map({ readBack.files[$0] == nil }) ?? true {
    problems.append("world: missing image file")
}
if let images = readBack.archive.world.images, !images.isEmpty, images.filter(\.isDefault).count != 1 {
    problems.append("world: needs exactly one default image")
}
for map in readBack.archive.maps {
    if let place = map.placeID, !pageIDs.contains(place) { problems.append("map \(map.name): missing place") }
    if map.imageFile.map({ readBack.files[$0] == nil }) ?? true { problems.append("map \(map.name): missing image file") }
    for pin in map.pins where pin.targetID.map({ !pageIDs.contains($0) }) ?? false { problems.append("map \(map.name): pin target missing") }
}
if !problems.isEmpty {
    print("Problems:\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
    exit(1)
}
let imageBytes = readBack.files.values.reduce(0) { $0 + $1.count }
print("Wrote \(output.path)")
print("  \(readBack.archive.pages.count) pages, \(readBack.archive.links.count) links, \(readBack.archive.maps.count) map, \(readBack.files.count) images (\(imageBytes / 1024) KB)")
