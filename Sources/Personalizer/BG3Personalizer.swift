import Foundation

// Baldur's Gate 3 personalizer (docs/PERSONALIZER.md §4). The text formatting is pure: it takes plain structs, so it
// is unit-testable without files. File reading and LSF extraction sit at the bottom.

struct BG3Member: Sendable, Equatable {
    var origin: String
    var mainClass: String?
    var subClass: String?
    var level: Int?
    var xp: Int?
}

/// What `SaveInfo.json` says.
struct BG3SaveInfo: Sendable, Equatable {
    var saveName: String?
    var difficulty: String?
    var gameVersion: String?
    var currentLevel: String?
    var members: [BG3Member]

    static func parse(_ data: Data) throws -> BG3SaveInfo {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersonalizerError.corrupt("SaveInfo.json is not an object")
        }
        func int(_ v: Any?) -> Int? { (v as? NSNumber).map { $0.intValue } }
        var members: [BG3Member] = []
        if let party = root["Active Party"] as? [String: Any], let chars = party["Characters"] as? [[String: Any]] {
            for c in chars {
                let first = (c["Classes"] as? [[String: Any]])?.first
                members.append(BG3Member(
                    origin: c["Origin"] as? String ?? "",
                    mainClass: (first?["Main"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    subClass: (first?["Sub"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    level: int(c["Level"]),
                    xp: int(c["Experience Points (Total)"])))
            }
        }
        let difficulty: String?
        if let list = root["Difficulty"] as? [String] { difficulty = list.joined(separator: ", ") }
        else { difficulty = root["Difficulty"] as? String }
        return BG3SaveInfo(saveName: root["Save Name"] as? String, difficulty: difficulty,
                           gameVersion: root["Game Version"] as? String, currentLevel: root["Current Level"] as? String,
                           members: members)
    }
}

/// One save, as the history needs it.
struct BG3SaveRecord: Sendable, Equatable {
    var modified: Date
    var hero: String
    var saveName: String
    var members: [BG3Member]

    var isAutosave: Bool { saveName.hasPrefix("AutoSave_") }

    /// "17h17m" from "Putrid Bog - 17h 17m new attempt".
    var playtime: String? {
        guard let m = saveName.firstMatch(of: /(\d+)h (\d+)m/) else { return nil }
        return "\(m.1)h\(m.2)m"
    }

    var heroMember: BG3Member? { members.first { $0.origin == "Generic" } }

    var classText: String {
        guard let h = heroMember else { return "-" }
        var parts: [String] = []
        if let l = h.level { parts.append("L\(l)") }
        if let main = h.mainClass { parts.append(h.subClass.map { "\(main)/\($0)" } ?? main) }
        return parts.isEmpty ? "-" : parts.joined(separator: " ")
    }

    var partyText: String {
        var companions: [String] = []
        var summons: [String] = []
        var seenHero = false
        for m in members {
            if m.origin == "Generic" {
                if seenHero { companions.append("custom character") } else { seenHero = true }
            } else if m.origin.contains("_") {
                let o = m.origin.lowercased()
                let label = o.contains("quasit") ? "quasit" : o.contains("wolf") ? "wolf" : o.contains("raven") ? "raven" : "summon"
                if !summons.contains(label) { summons.append(label) }
            } else if !m.origin.isEmpty {
                companions.append(m.origin)
            }
        }
        var text = companions.isEmpty ? "solo" : "with " + companions.joined(separator: ", ")
        for s in summons { text += " +\(s)" }
        return text
    }
}

enum BG3Format {
    static let maxHistoryLines = 250

    static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    static func day(_ date: Date, timeZone: TimeZone) -> String { String(stamp(date, timeZone: timeZone).prefix(10)) }

    /// §4.1. `records` may be in any order; they are sorted by modification date.
    static func history(_ unsorted: [BG3SaveRecord], timeZone: TimeZone = .current) -> String {
        let records = unsorted.sorted { $0.modified < $1.modified }
        guard let first = records.first, let last = records.last else { return "No saves." }

        var counts: [String: Int] = [:]
        var order: [String] = []
        for r in records { if counts[r.hero] == nil { order.append(r.hero) }; counts[r.hero, default: 0] += 1 }
        let heroes = order.sorted { counts[$0, default: 0] > counts[$1, default: 0] }
            .map { "\($0) (\(counts[$0, default: 0]) save\(counts[$0] == 1 ? "" : "s"))" }.joined(separator: ", ")

        var lines: [String] = []
        var i = 0
        while i < records.count {
            let r = records[i]
            var j = i
            if r.isAutosave {
                while j + 1 < records.count, records[j + 1].isAutosave, records[j + 1].hero == r.hero,
                      day(records[j + 1].modified, timeZone: timeZone) == day(r.modified, timeZone: timeZone) { j += 1 }
            }
            let shown = records[j]
            let name = j > i ? "\(j - i + 1) autosaves" : "\"\(shown.saveName)\""
            lines.append([stamp(shown.modified, timeZone: timeZone), shown.hero, name, shown.playtime ?? "-", shown.classText, shown.partyText]
                .joined(separator: " | "))
            i = j + 1
        }

        var out = [
            "Heroes: \(heroes)",
            "First save: \(stamp(first.modified, timeZone: timeZone)); last save: \(stamp(last.modified, timeZone: timeZone))",
            "Total saves: \(records.count)",
            "Note: a lower playtime than the previous save by the same hero means the player reloaded an earlier save.",
            "Columns: date | hero | save name | playtime | hero class | party",
        ]
        if lines.count > maxHistoryLines {
            out.append("(Showing only the most recent \(maxHistoryLines) lines.)")
            lines = Array(lines.suffix(maxHistoryLines))
        }
        return (out + [""] + lines).joined(separator: "\n")
    }

    // MARK: Latest save

    static let skillNames = [0: "Deception", 1: "Intimidation", 2: "Performance", 3: "Persuasion", 4: "Acrobatics",
                             5: "Sleight of Hand", 6: "Stealth", 7: "Arcana", 8: "History", 9: "Investigation",
                             10: "Nature", 11: "Religion", 12: "Athletics", 13: "Animal Handling", 14: "Insight",
                             15: "Medicine", 16: "Perception", 17: "Survival"]
    static let abilityNames = [1: "Strength", 2: "Dexterity", 3: "Constitution", 4: "Intelligence", 5: "Wisdom", 6: "Charisma"]

    static func rollName(skill: Int, ability: Int) -> String {
        if skill == 18 { return abilityNames[ability].map { "\($0) check" } ?? "Raw ability check" }
        return skillNames[skill] ?? "Skill \(skill)"
    }

    /// §4.2. `journal == nil` means Globals.lsf could not be read.
    static func latest(info: BG3SaveInfo, hero: String, saveName: String, journal: BG3Journal?) -> String {
        var out: [String] = ["Save: \"\(saveName)\" (hero: \(hero))"]
        if let d = info.difficulty { out.append("Difficulty: \(d)") }
        if let v = info.gameVersion { out.append("Game version: \(v)") }
        if let l = info.currentLevel { out.append("Current area: \(l)") }
        var heroSeen = false
        for m in info.members {
            let isHero = m.origin == "Generic" && !heroSeen
            if isHero { heroSeen = true }
            let who = isHero ? "\(hero) (hero)" : (m.origin == "Generic" ? "custom character" : m.origin)
            var bits: [String] = []
            if let main = m.mainClass { bits.append(m.subClass.map { "\(main)/\($0)" } ?? main) }
            if let l = m.level { bits.append("level \(l)") }
            if let xp = m.xp { bits.append("\(xp) XP") }
            out.append("Party member: \(who)" + (bits.isEmpty ? "" : ": " + bits.joined(separator: ", ")))
        }
        guard let journal else { out.append("Journal unavailable."); return out.joined(separator: "\n") }

        func visible(_ q: String) -> Bool { !q.hasPrefix("HIDDEN_") }
        var byCategory: [String: [String]] = [:]
        var categoryOrder: [String] = []
        for c in journal.categories where visible(c.quest) {
            if byCategory[c.category] == nil { categoryOrder.append(c.category) }
            byCategory[c.category, default: []].append(c.quest)
        }
        if let done = byCategory["CompletedQuests"] {
            out.append("Completed quests (\(done.count)): " + done.joined(separator: ", "))
        } else {
            out.append("Completed quests (0)")
        }
        for cat in categoryOrder where cat != "CompletedQuests" {
            let qs = byCategory[cat, default: []]
            out.append("Quest category \(cat) (\(qs.count)): " + qs.joined(separator: ", "))
        }
        let open = journal.progress.filter { visible($0.quest) && !$0.objective.hasSuffix("_COMPLETION") }
        if open.isEmpty {
            out.append("Open questlines (0)")
        } else {
            out.append("Open questlines (\(open.count)): " + open.map { "\($0.quest) → \($0.objective)" }.joined(separator: "; "))
        }

        // Dialogs
        let names = journal.dialogs.map { d in d.file.hasSuffix(".lsj") ? String(d.file.dropLast(4)) : d.file }
        let days = journal.dialogs.compactMap(\.day)
        if let lo = days.min(), let hi = days.max() { out.append("In-game days seen in the dialog log: \(lo) to \(hi)") }
        struct Run { var name: String; var count: Int; var firstDay: Int?; var lastDay: Int? }
        var runs: [Run] = []
        for (n, d) in zip(names, journal.dialogs) {
            if var r = runs.last, r.name == n {
                r.count += 1; r.lastDay = d.day ?? r.lastDay
                runs[runs.count - 1] = r
            } else {
                runs.append(Run(name: n, count: 1, firstDay: d.day, lastDay: d.day))
            }
        }
        let recent = runs.suffix(40).map { r -> String in
            var s = r.name + (r.count > 1 ? " ×\(r.count)" : "")
            if let a = r.firstDay { s += (r.lastDay ?? a) == a ? " (day \(a))" : " (day \(a)-\(r.lastDay ?? a))" }
            return s
        }
        out.append("Recent conversations, oldest first (in-game day): " + (recent.isEmpty ? "none" : recent.joined(separator: ", ")))
        var freq: [String: Int] = [:]
        for n in names { freq[n, default: 0] += 1 }
        let top = freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5)
        if !top.isEmpty { out.append("Most frequent dialogs: " + top.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")) }

        // Dice
        struct Key: Hashable { var name: String; var passive: Bool }
        var tally: [Key: (pass: Int, fail: Int)] = [:]
        for r in journal.rolls {
            let k = Key(name: rollName(skill: r.skill, ability: r.ability), passive: r.passive)
            var t = tally[k, default: (0, 0)]
            if r.success { t.pass += 1 } else { t.fail += 1 }
            tally[k] = t
        }
        if tally.isEmpty {
            out.append("Dice rolls: none recorded")
        } else {
            let parts = tally.sorted {
                let a = $0.value.pass + $0.value.fail, b = $1.value.pass + $1.value.fail
                if a != b { return a > b }
                if $0.key.passive != $1.key.passive { return !$0.key.passive }
                return $0.key.name < $1.key.name
            }.map { k, t -> String in
                var bits: [String] = []
                if t.pass > 0 { bits.append("\(t.pass) passed") }
                if t.fail > 0 { bits.append("\(t.fail) failed") }
                return "\(k.name) \(bits.joined(separator: " / "))" + (k.passive ? " (passive)" : "")
            }
            out.append("Dice rolls (\(journal.rolls.count) total): " + parts.joined(separator: "; "))
        }
        return out.joined(separator: "\n")
    }

    static func fingerprint(saveCount: Int, latest: Date) -> String { "\(saveCount):\(Int(latest.timeIntervalSince1970))" }
}

// MARK: - Journal (extracted from Globals.lsf)

struct BG3Journal: Sendable, Equatable {
    struct Roll: Sendable, Equatable { var skill: Int, ability: Int, passive: Bool, success: Bool }
    struct Dialog: Sendable, Equatable { var file: String, day: Int? }
    struct Category: Sendable, Equatable { var quest: String, category: String }
    struct Progress: Sendable, Equatable { var quest: String, objective: String }
    var categories: [Category]
    var progress: [Progress]
    var dialogs: [Dialog]
    var rolls: [Roll]

    /// Reads the Sendable journal out of the (non-Sendable) LSF tree. `nil` when there is no Journal root.
    static func extract(from roots: [LSFNode]) -> BG3Journal? {
        guard let journal = roots.first(where: { $0.name == "Journal" }) else { return nil }
        func str(_ n: LSFNode, _ key: String) -> String? { if case .string(let s)? = n.attributes[key] { return s } else { return nil } }
        func int(_ n: LSFNode, _ key: String) -> Int? { if case .int(let v)? = n.attributes[key] { return Int(v) } else { return nil } }
        func flag(_ n: LSFNode, _ key: String) -> Bool { if case .bool(let b)? = n.attributes[key] { return b } else { return false } }

        var categories: [Category] = []
        for c in journal.child(named: "QuestCategories")?.children(named: "QuestCategory") ?? [] {
            if let q = str(c, "QuestID"), let cat = str(c, "CategoryID") { categories.append(Category(quest: q, category: cat)) }
        }
        var progress: [Progress] = []
        for p in journal.child(named: "Quests")?.descendants.filter({ $0.name == "QuestsProgress" }) ?? [] {
            guard let key = str(p, "MapKey"),
                  let quest = p.descendants.first(where: { $0.name == "Quest" && str($0, "ObjectiveID") != nil }),
                  let objective = str(quest, "ObjectiveID") else { continue }
            progress.append(Progress(quest: key, objective: objective))
        }
        var dialogs: [Dialog] = []
        var rolls: [Roll] = []
        for log in journal.child(named: "DialogLogs")?.children(named: "DialogLog") ?? [] {
            dialogs.append(Dialog(file: str(log, "DLOG_FileName") ?? "?", day: int(log, "DLOG_GameDay")))
            for line in log.descendants where line.name == "DialogLogLine" {
                let skill = int(line, "RollSkill") ?? 19, ability = int(line, "RollAbility") ?? 0
                guard skill != 19 || ability != 0 else { continue }
                rolls.append(Roll(skill: skill, ability: ability, passive: flag(line, "RollIsPassive"), success: flag(line, "RollIsSuccess")))
            }
        }
        return BG3Journal(categories: categories, progress: progress, dialogs: dialogs, rolls: rolls)
    }
}

// MARK: - Files

struct BG3Personalizer: GamePersonalizer {
    let appID = 1086940
    let displayName = "Baldur's Gate 3"

    /// `<Hero>-<digits>__<Save Name>`
    static func parseFolder(_ name: String) -> (hero: String, saveName: String) {
        if let m = name.firstMatch(of: /^(.*)-(\d+)__(.*)$/) { return (String(m.1), String(m.3)) }
        return (name, name)
    }

    func digest(steamRoot: URL) throws -> GameDigest? {
        let fm = FileManager.default
        let userdata = steamRoot.appending(path: "userdata", directoryHint: .isDirectory)
        guard let users = try? fm.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil) else { return nil }

        struct Found { var url: URL; var modified: Date; var hero: String; var folderName: String }
        var found: [Found] = []
        for user in users {
            let story = user.appending(path: "\(appID)/remote/_SAVE_Public/Savegames/Story", directoryHint: .isDirectory)
            guard let folders = try? fm.contentsOfDirectory(at: story, includingPropertiesForKeys: nil) else { continue }
            for folder in folders {
                guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                let parsed = Self.parseFolder(folder.lastPathComponent)
                for file in files where file.pathExtension.lowercased() == "lsv" {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    found.append(Found(url: file, modified: modified, hero: parsed.hero, folderName: parsed.saveName))
                }
            }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.modified < $1.modified }

        var records: [BG3SaveRecord] = []
        var latestInfo: (info: BG3SaveInfo, found: Found, name: String)?
        for f in found {
            guard let pkg = try? LSPKPackage(url: f.url),
                  let data = try? pkg.data(for: "SaveInfo.json"),
                  let info = try? BG3SaveInfo.parse(data) else { continue }
            let name = info.saveName ?? f.folderName
            records.append(BG3SaveRecord(modified: f.modified, hero: f.hero, saveName: name, members: info.members))
            latestInfo = (info, f, name)
        }
        guard let latest = latestInfo else { throw PersonalizerError.corrupt("no readable saves") }

        var journal: BG3Journal?
        if let pkg = try? LSPKPackage(url: latest.found.url),
           let globals = try? pkg.data(for: "Globals.lsf"),
           let roots = try? LSF.parse(globals, keepOnly: ["Journal"]) {
            journal = BG3Journal.extract(from: roots)
        }
        return GameDigest(
            history: BG3Format.history(records),
            latest: BG3Format.latest(info: latest.info, hero: latest.found.hero, saveName: latest.name, journal: journal),
            fingerprint: BG3Format.fingerprint(saveCount: records.count, latest: latest.found.modified),
            saveCount: records.count)
    }
}
