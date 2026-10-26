import Foundation
import SwiftData

/// A maintenance schedule as stored in the bundled JSON files and as returned by the AI importer.
struct ScheduleTemplate: Codable, Identifiable, Hashable {
    var id: String
    var make: String
    var model: String
    var aliases: [String]?
    var generation: String?
    var yearFrom: Int?
    var yearTo: Int?
    var kind: String?
    var fuel: String?
    var source: String?
    var sourceURLs: [String]?
    var disclaimer: String?
    var tasks: [TaskTemplate]
    var specs: [SpecTemplate]?

    var title: String {
        var t = "\(make) \(model)"
        if let g = generation, !g.isEmpty { t += " — \(LS(g))" }
        return t
    }
}

struct TaskTemplate: Codable, Hashable, Identifiable {
    var id: String { title + (actionRaw ?? "") }
    var title: String
    var actionRaw: String?
    var category: String?
    var intervalKm: Int?
    var intervalMonths: Int?
    var firstKm: Int?
    var firstMonths: Int?
    var oneTime: Bool?
    var notes: String?
    var spec: String?
    var sourceRef: String?

    enum CodingKeys: String, CodingKey {
        case title, category, intervalKm, intervalMonths, firstKm, firstMonths, oneTime, notes, spec, sourceRef
        case actionRaw = "action"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        actionRaw = try? c.decodeIfPresent(String.self, forKey: .actionRaw)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        intervalKm = Self.flexibleInt(c, .intervalKm)
        intervalMonths = Self.flexibleInt(c, .intervalMonths)
        firstKm = Self.flexibleInt(c, .firstKm)
        firstMonths = Self.flexibleInt(c, .firstMonths)
        oneTime = try? c.decodeIfPresent(Bool.self, forKey: .oneTime)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        spec = try? c.decodeIfPresent(String.self, forKey: .spec)
        sourceRef = try? c.decodeIfPresent(String.self, forKey: .sourceRef)
    }

    /// Accepts 12000, 12000.0 or "12000" (AI output is not always strictly typed). 0 means "none".
    private static func flexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i > 0 ? i : nil }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d > 0 ? Int(d) : nil }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let digits = s.filter(\.isNumber)
            if let i = Int(digits), i > 0 { return i }
        }
        return nil
    }

    var intervalText: String {
        if oneTime == true {
            var p: [String] = []
            if let k = firstKm { p.append(L("at %@", Fmt.km(k))) }
            if let m = firstMonths { p.append(Fmt.months(m)) }
            return L("Once, %@", p.joined(separator: " \(L("or")) "))
        }
        var p: [String] = []
        if let k = intervalKm { p.append(Fmt.km(k)) }
        if let m = intervalMonths { p.append(Fmt.months(m)) }
        return p.isEmpty ? L("No interval") : L("Every %@", p.joined(separator: " \(L("or")) "))
    }
}

struct SpecTemplate: Codable, Hashable {
    var group: String
    var title: String
    var value: String
}

@MainActor
final class ScheduleLibrary {
    static let shared = ScheduleLibrary()

    let templates: [ScheduleTemplate]

    private init() {
        var urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        urls += Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Schedules") ?? []
        let decoder = JSONDecoder()
        var seen = Set<String>()
        var result: [ScheduleTemplate] = []
        for url in urls where url.lastPathComponent.hasPrefix("schedule-") {
            guard let data = try? Data(contentsOf: url),
                  let t = try? decoder.decode(ScheduleTemplate.self, from: data),
                  !seen.contains(t.id) else { continue }
            seen.insert(t.id)
            result.append(t)
        }
        templates = result.sorted { $0.title < $1.title }
    }

    /// Templates ranked by how well they match the vehicle description (best first). Non-matching makes are excluded.
    func matches(make: String, model: String, year: Int, fuel: FuelType) -> [ScheduleTemplate] {
        let mk = make.trimmingCharacters(in: .whitespaces).lowercased()
        let md = model.trimmingCharacters(in: .whitespaces).lowercased()
        guard !mk.isEmpty || !md.isEmpty else { return [] }

        let scored: [(ScheduleTemplate, Int)] = templates.compactMap { t in
            var score = 0
            let tMake = t.make.lowercased()
            if !mk.isEmpty {
                guard tMake.hasPrefix(mk) || mk.hasPrefix(tMake) else { return nil }
                score += 10
            }
            if !md.isEmpty {
                let names = [t.model.lowercased()] + (t.aliases ?? [])
                let compact = md.replacingOccurrences(of: " ", with: "")
                let hit = names.contains { n in
                    let nc = n.replacingOccurrences(of: " ", with: "")
                    return compact.contains(nc) || nc.contains(compact)
                }
                guard hit else { return nil }
                score += 10
                // Generation hints such as "mk7" / "mk8" in the user's model text.
                for g in ["mk6", "mk7", "mk8"] where compact.contains(g) {
                    score += (t.aliases ?? []).contains { $0.replacingOccurrences(of: " ", with: "") == "fiesta\(g)" } ? 6 : -6
                }
            }
            if year > 0 {
                if let from = t.yearFrom, let to = t.yearTo {
                    score += (from...to).contains(year) ? 5 : -5
                }
            }
            if let f = t.fuel {
                score += f == fuel.rawValue ? 3 : -3
            }
            return (t, score)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

// MARK: - Applying a template to a vehicle

enum ScheduleApplier {
    /// Adds the template's tasks/specs to the vehicle. When `replace` is true, existing non-custom tasks
    /// that have no history are removed first.
    @MainActor
    static func apply(_ template: ScheduleTemplate, tasks selected: [TaskTemplate]? = nil,
                      to vehicle: Vehicle, in context: ModelContext,
                      replace: Bool) {
        if replace {
            for t in vehicle.tasks where !t.isCustom && t.records.isEmpty {
                context.delete(t)
            }
            for s in vehicle.specs { context.delete(s) }
        }

        let existingTitles = Set(vehicle.tasks.filter { !$0.isDeleted }.map { $0.title.lowercased() })
        let startOrder = (vehicle.tasks.map(\.sortOrder).max() ?? 0) + 1
        for (i, tt) in (selected ?? template.tasks).enumerated() where replace || !existingTitles.contains(tt.title.lowercased()) {
            let task = MaintenanceTask(title: tt.title,
                                       action: TaskAction(rawValue: (tt.actionRaw ?? "").lowercased()) ?? .inspect,
                                       category: (tt.category ?? "general").lowercased())
            task.intervalKm = tt.intervalKm
            task.intervalMonths = tt.intervalMonths
            task.firstKm = tt.firstKm
            task.firstMonths = tt.firstMonths
            task.oneTime = tt.oneTime ?? false
            task.notes = tt.notes ?? ""
            task.spec = tt.spec ?? ""
            task.sourceRef = tt.sourceRef ?? ""
            task.sortOrder = startOrder + i
            context.insert(task)
            task.vehicle = vehicle
        }

        for (i, sp) in (template.specs ?? []).enumerated() {
            let note = SpecNote(group: sp.group, title: sp.title, value: sp.value, sortOrder: i)
            context.insert(note)
            note.vehicle = vehicle
        }

        vehicle.scheduleSource = template.source ?? template.title
        vehicle.scheduleSourceURLs = template.sourceURLs ?? []
        vehicle.scheduleDisclaimer = template.disclaimer ?? ""
    }
}
