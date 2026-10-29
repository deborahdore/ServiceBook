import Foundation
import Observation
import SwiftData

/// A maintenance schedule as stored in the catalog files (catalog/schedules on GitHub) and as returned by the AI importer.
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
    var generic: Bool?
    var version: Int?
    /// [language: [English text: translation]] for every text in the schedule (catalog files only).
    var translations: [String: [String: String]]?

    var title: String {
        var t = "\(make) \(LS(model))"
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

/// One schedule as listed in catalog/index.json: enough to match and show it before it is downloaded.
struct CatalogEntry: Codable, Identifiable, Hashable {
    var id: String
    var make: String
    var makeAliases: [String]?
    var model: String
    var aliases: [String]?
    var generation: String?
    var yearFrom: Int?
    var yearTo: Int?
    var kind: String?
    var fuel: String?
    /// Brand-wide plan: matches every model of the make, ranked below model-specific schedules.
    var generic: Bool?
    var tasks: Int
    var specs: Int
    var version: Int

    var title: String {
        var t = "\(make) \(LS(model))"
        if let g = generation, !g.isEmpty { t += " — \(LS(g))" }
        return t
    }
}

struct CatalogIndex: Codable {
    var schedules: [CatalogEntry]
    /// Translations of the model names and generations shown before a schedule is downloaded.
    var translations: [String: [String: String]]?
}

/// Translations carried by the downloaded catalog files ([language: [English text: translation]]).
/// Read by `LS`, so saved items follow the app language even offline.
final class ScheduleTranslations: @unchecked Sendable {
    static let shared = ScheduleTranslations()
    private var table: [String: [String: String]] = [:]
    private let lock = NSLock()

    func add(_ translations: [String: [String: String]]?) {
        guard let translations else { return }
        lock.lock(); defer { lock.unlock() }
        for (lang, texts) in translations { table[lang, default: [:]].merge(texts) { _, new in new } }
    }

    func lookup(_ text: String, _ lang: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return table[lang]?[text]
    }
}

enum CatalogError: LocalizedError {
    case download
    var errorDescription: String? { L("Couldn't download the schedule. Check your connection and try again.") }
}

/// The schedule catalog lives on GitHub (catalog/ in the repo). The index is refreshed when the app needs it
/// and each schedule is downloaded only when the user picks it; both are cached for offline use.
@MainActor @Observable
final class ScheduleLibrary {
    static let shared = ScheduleLibrary()
    static let baseURL = URL(string: "https://raw.githubusercontent.com/deborahdore/ServiceBook/main/catalog/")!

    var entries: [CatalogEntry] = []
    private(set) var isLoading = false
    private(set) var failed = false
    private var lastRefresh: Date?
    private let dir: URL

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("schedules"), withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
           let index = try? decoder.decode(CatalogIndex.self, from: data) {
            entries = index.schedules
            ScheduleTranslations.shared.add(index.translations)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("schedules"),
                                                                    includingPropertiesForKeys: nil)) ?? []
        for url in files {
            if let data = try? Data(contentsOf: url), let t = try? decoder.decode(ScheduleTemplate.self, from: data) {
                ScheduleTranslations.shared.add(t.translations)
            }
        }
    }

    func entry(_ id: String) -> CatalogEntry? { entries.first { $0.id == id } }

    /// Downloads the index again, at most every 6 hours unless forced.
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, !entries.isEmpty, let last = lastRefresh, Date().timeIntervalSince(last) < 6 * 3600 { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await fetch("index.json")
            let index = try JSONDecoder().decode(CatalogIndex.self, from: data)
            try? data.write(to: dir.appendingPathComponent("index.json"))
            ScheduleTranslations.shared.add(index.translations)
            entries = index.schedules
            lastRefresh = Date()
            failed = false
        } catch {
            failed = true
        }
    }

    /// The full schedule: from the cache when its version matches the index, else downloaded (falls back to an older cached copy).
    func template(for entry: CatalogEntry) async throws -> ScheduleTemplate {
        let file = dir.appendingPathComponent("schedules/\(entry.id).json")
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(ScheduleTemplate.self, from: $0) }
        if let cached, cached.version == entry.version { return cached }
        do {
            let data = try await fetch("schedules/\(entry.id).json")
            let t = try JSONDecoder().decode(ScheduleTemplate.self, from: data)
            try? data.write(to: file)
            ScheduleTranslations.shared.add(t.translations)
            return t
        } catch {
            if let cached { return cached }
            throw CatalogError.download
        }
    }

    private func fetch(_ path: String) async throws -> Data {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CatalogError.download }
        return data
    }

    /// Catalog entries ranked by how well they match the vehicle (best first). Other makes and vehicle types are
    /// excluded; brand-wide plans match any model of the make and rank below model-specific schedules.
    func matches(make: String, model: String, year: Int, fuel: FuelType, kind: VehicleKind? = nil) -> [CatalogEntry] {
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" }
        }
        let mk = norm(make)
        let md = norm(model)
        guard !mk.isEmpty || !md.isEmpty else { return [] }
        let wantedKind: String? = switch kind {
        case .car, .van: "car"
        case .motorcycle, .scooter: "motorcycle"
        default: nil
        }

        let scored: [(CatalogEntry, Int)] = entries.compactMap { t in
            if let wantedKind, let k = t.kind, k != wantedKind { return nil }
            var score = 0
            if !mk.isEmpty {
                let makes = [norm(t.make)] + (t.makeAliases ?? []).map(norm)
                guard makes.contains(where: { $0.hasPrefix(mk) || mk.hasPrefix($0) }) else { return nil }
                score += 10
            }
            if t.generic == true {
                guard !mk.isEmpty else { return nil }
                score += 5
            } else if !md.isEmpty {
                let names = ([t.model] + (t.aliases ?? [])).map(norm)
                guard names.contains(where: { md.contains($0) || $0.contains(md) }) else { return nil }
                // The longest name found in the user's text wins: "Yaris Cross" beats "Yaris".
                score += 20 + min(names.filter { md.contains($0) }.map(\.count).max() ?? 0, 12)
                // Generation hints such as "mk7" / "mk8" in the user's model text.
                if let r = md.range(of: #"mk\d+"#, options: .regularExpression) {
                    let g = String(md[r])
                    score += names.contains { $0.contains(g) } ? 6 : -6
                }
            }
            if year > 0 {
                if let from = t.yearFrom, year < from { score -= 5 }
                else if let to = t.yearTo, year > to { score -= 5 }
                else if t.yearFrom != nil || t.yearTo != nil { score += 5 }
            }
            if let f = t.fuel {
                if f == fuel.rawValue { score += 3 }
                else if fuel == .hybrid && f == "petrol" { score += 1 }
                else { score -= fuel == .electric ? 8 : 3 }
            }
            return (t, score)
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }.map(\.0)
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
