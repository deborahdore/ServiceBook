import Foundation
import PDFKit

/// Builds a maintenance schedule with Claude: either by searching the web for the
/// vehicle's owner's manual, or by reading a manual PDF the user provides.
/// Claude returns the schedule by calling the strict `submit_schedule` tool, so the
/// result always matches the schema below.
struct ManualImporter {
    struct Result {
        var template: ScheduleTemplate
        var manualURLs: [String]
        var summary: String
        var usage: AIUsage
        var model: String
    }

    enum ImportError: LocalizedError {
        case missingKey
        case unreadablePDF
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: L("Set up the Claude connection in Settings to use AI import.")
            case .unreadablePDF: L("Could not read any text from this PDF, and it is too large to send as images (over 100 pages). Try a PDF of just the maintenance chapter.")
            case .decode(let msg): L("Could not understand the schedule returned by the AI: %@", msg)
            }
        }
    }

    struct VehicleDescription {
        var make: String
        var model: String
        var year: Int
        var variant: String
        var fuel: String
        var kind: String

        var text: String {
            var s = "\(make) \(model)"
            if year > 0 { s += " (model year \(year))" }
            if !variant.isEmpty { s += ", engine/variant: \(variant)" }
            s += ", fuel: \(fuel), type: \(kind)"
            return s
        }
    }

    static let toolName = "submit_schedule"

    static let actions = ["inspect", "check", "replace", "lubricate", "clean", "adjust", "service"]
    static let categories = ["oil", "filters", "brakes", "tyres", "wheels", "chain", "cooling", "fuel", "ignition",
                             "electrical", "engine", "suspension", "steering", "transmission", "climate", "body",
                             "chassis", "safety", "emissions", "controls", "owner", "legal", "service", "general"]

    /// JSON schema of the submit tool. Optional fields are simply not required (no nullable unions),
    /// which keeps the schema within the strict-mode limits.
    static func submitTool(strict: Bool) -> [String: Any] {
        func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
        func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }

        let task: [String: Any] = [
            "type": "object",
            "properties": [
                "title": str("Component or check, e.g. 'Engine oil' or 'Brake pad wear'."),
                "action": ["type": "string", "enum": actions] as [String: Any],
                "category": ["type": "string", "enum": categories] as [String: Any],
                "intervalKm": int("Repeat interval in kilometres. Omit if the item has no distance interval."),
                "intervalMonths": int("Repeat interval in months. Omit if the item has no time interval."),
                "firstKm": int("First occurrence in km when different from the interval (e.g. run-in service)."),
                "firstMonths": int("First occurrence in months when different from the interval."),
                "oneTime": ["type": "boolean", "description": "True for items done only once, such as the initial service."] as [String: Any],
                "notes": str("Important notes from the manual: severe-use advice, conditions, warnings."),
                "spec": str("Fluid grade, capacity, part number, torque, clearance…"),
                "sourceRef": str("Where it comes from, e.g. 'Owner's manual p. 92'."),
            ] as [String: Any],
            "required": ["title", "action", "category"],
            "additionalProperties": false,
        ]
        let spec: [String: Any] = [
            "type": "object",
            "properties": [
                "group": str("Fluids, Tyres, Torques, Electrical, Owner checks or Notes."),
                "title": str("e.g. 'Engine oil'"),
                "value": str("e.g. 'SAE 10W-40, 2.0 L'"),
            ] as [String: Any],
            "required": ["group", "title", "value"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "make": str("Manufacturer"),
                "model": str("Model name"),
                "generation": str("Generation / version / years covered"),
                "summary": str("2–3 sentences for the user: what was found and any caveats."),
                "source": str("Short description of the documents used."),
                "sourceURLs": ["type": "array", "items": ["type": "string"], "description": "URLs of the documents used."] as [String: Any],
                "manualURLs": ["type": "array", "items": ["type": "string"], "description": "Direct links to owner's manual or maintenance PDFs."] as [String: Any],
                "disclaimer": str("Short caveat shown to the user."),
                "tasks": ["type": "array", "items": task] as [String: Any],
                "specs": ["type": "array", "items": spec] as [String: Any],
            ] as [String: Any],
            "required": ["make", "model", "summary", "tasks"],
            "additionalProperties": false,
        ]
        var tool: [String: Any] = [
            "name": toolName,
            "description": "Submit the complete maintenance schedule and specifications for the vehicle. Call this exactly once, at the end.",
            "input_schema": schema,
        ]
        if strict { tool["strict"] = true }
        return tool
    }

    private static var rules: String { """
    Rules for the schedule:
    - Use kilometres. Convert miles to km (1 mi = 1.609 km) and round sensibly (12,500 mi → 20,000 km).
    - List every item of the periodic maintenance chart as its own task (one task per component and action), \
    including inspections, not only replacements.
    - Intervals are "whichever comes first": give both km and months when the manual gives both.
    - Put fluid specifications and capacities, tyre sizes and pressures, and owner checks \
    (daily / before riding / monthly) in specs.
    - Never invent numbers. If something is unclear, leave the field out and explain in notes.
    - Write titles, notes, specs, the summary and the disclaimer in \(AppLanguage.englishName).
    """ }

    let client: ClaudeClient

    init() throws {
        guard let client = AppSettings.client else { throw ImportError.missingKey }
        self.client = client
    }

    // MARK: Search online

    func searchOnline(for vehicle: VehicleDescription, onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> Result {
        let system = """
        You are a vehicle maintenance expert. You find the official manufacturer maintenance schedule \
        (owner's manual, service booklet or maintenance chart) for a specific vehicle and submit it with \(Self.toolName).
        """
        var region = ""
        if AppSettings.useRegion, let code = AppSettings.regionCode {
            region = " The owner lives in \(Locale(identifier: "en").localizedString(forRegionCode: code) ?? code) (\(code)): prefer that market's schedule when it differs."
        }
        let prompt = """
        Vehicle: \(vehicle.text).\(region)

        1. Search the web for the official owner's manual or maintenance schedule of this exact vehicle. \
        Prefer the manufacturer's own website or PDFs; use other sources only to fill gaps, and say so in notes.
        2. Read the periodic maintenance chart / service schedule. Avoid fetching enormous PDFs \
        (more than ~100 pages) when a dedicated maintenance page or service booklet exists.
        3. Call \(Self.toolName) with the complete schedule.

        \(Self.rules)
        """
        let searches = AppSettings.maxSearches
        var search: [String: Any] = ["type": "web_search_20250305", "name": "web_search", "max_uses": searches]
        if AppSettings.useRegion, let code = AppSettings.regionCode {
            search["user_location"] = ["type": "approximate", "country": code]
        }
        let fetch: [String: Any] = ["type": "web_fetch_20250910", "name": "web_fetch",
                                    "max_uses": max(3, searches * 3 / 4), "max_content_tokens": 60_000]

        onEvent(.status(L("Asking Claude to find the manual…")))
        let outcome = try await runWithStrictFallback(system: system, content: [["type": "text", "text": prompt]],
                                                      otherTools: [search, fetch], force: false, onEvent: onEvent)
        return try Self.result(from: outcome, vehicle: vehicle, model: client.model)
    }

    // MARK: Import PDF

    func importPDF(data: Data, vehicle: VehicleDescription, onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> Result {
        onEvent(.status(L("Reading the PDF…")))
        let excerpt = Self.relevantText(from: data)
        let system = "You are a vehicle maintenance expert who converts owner's manuals into structured maintenance schedules."

        var content: [[String: Any]]
        if let excerpt, excerpt.count > 500 {
            content = [["type": "text", "text": """
                Vehicle: \(vehicle.text).
                Below are the pages of its owner's manual that mention maintenance (page numbers in brackets).

                <manual>
                \(excerpt)
                </manual>

                Extract the complete maintenance schedule and important specifications, and call \(Self.toolName).
                \(Self.rules)
                """]]
        } else if data.count < 30_000_000, (PDFDocument(data: data)?.pageCount ?? 0) <= 100 {
            // Scanned / image-only PDF: send it directly so Claude can read the page images.
            content = [
                ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]] as [String: Any],
                ["type": "text", "text": "Vehicle: \(vehicle.text). This is its owner's manual or service booklet. Extract the complete maintenance schedule and important specifications, and call \(Self.toolName).\n\(Self.rules)"],
            ]
        } else {
            throw ImportError.unreadablePDF
        }

        onEvent(.status(L("Claude is reading the maintenance pages…")))
        let outcome = try await runWithStrictFallback(system: system, content: content, otherTools: [], force: true, onEvent: onEvent)
        return try Self.result(from: outcome, vehicle: vehicle, model: client.model)
    }

    /// Strict tool use guarantees the schema; if the API rejects strict mode for this
    /// model or tool combination, retry once without it (the decoder is tolerant).
    private func runWithStrictFallback(system: String, content: [[String: Any]], otherTools: [[String: Any]],
                                       force: Bool, onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> ClaudeClient.Outcome {
        do {
            return try await client.run(system: system, userContent: content,
                                        tools: otherTools + [Self.submitTool(strict: true)],
                                        finalTool: Self.toolName, forceFinalTool: force, onEvent: onEvent)
        } catch ClaudeClient.ClientError.badRequest(let message) where message.lowercased().contains("strict")
                                                                    || message.lowercased().contains("schema") {
            onEvent(.status(L("Retrying without strict schema…")))
            return try await client.run(system: system, userContent: content,
                                        tools: otherTools + [Self.submitTool(strict: false)],
                                        finalTool: Self.toolName, forceFinalTool: force, onEvent: onEvent)
        }
    }

    static let keywords = ["maintenance", "service schedule", "periodic", "interval", "entretien", "manutenzione",
                           "tagliando", "wartung", "inspection", "replace", "capacit", "specification", "km",
                           "revisione", "sostituire", "controllare", "vidange", "remplacer", "mantenimiento",
                           "sustituir", "manutenção", "substituir"]

    /// How much a page talks about maintenance (keyword hits).
    static func score(_ text: String) -> Int {
        let lower = text.lowercased()
        return keywords.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
    }

    /// Picks the manual pages most likely to contain the maintenance schedule and specs.
    static func relevantText(from data: Data, maxCharacters: Int = 150_000) -> String? {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return nil }
        var pages: [(index: Int, text: String, score: Int)] = []
        for i in 0..<doc.pageCount {
            guard let text = doc.page(at: i)?.string, !text.isEmpty else { continue }
            pages.append((i, text, score(text)))
        }
        guard !pages.isEmpty else { return nil }

        let total = pages.reduce(0) { $0 + $1.text.count }
        var chosen: [(index: Int, text: String, score: Int)]
        if total <= maxCharacters {
            chosen = pages
        } else {
            chosen = []
            var used = 0
            for p in pages.sorted(by: { $0.score > $1.score }) where p.score > 0 {
                if used + p.text.count > maxCharacters { continue }
                chosen.append(p)
                used += p.text.count
            }
            chosen.sort { $0.index < $1.index }
        }
        return chosen.map { "[page \($0.index + 1)]\n\($0.text)" }.joined(separator: "\n\n")
    }

    // MARK: Decoding

    private struct Envelope: Decodable {
        var make: String?
        var model: String?
        var generation: String?
        var source: String?
        var sourceURLs: [String]?
        var manualURLs: [String]?
        var summary: String?
        var disclaimer: String?
        var tasks: [TaskTemplate]
        var specs: [SpecTemplate]?
    }

    static func result(from outcome: ClaudeClient.Outcome, vehicle: VehicleDescription, model: String) throws -> Result {
        let data: Data
        if let input = outcome.toolInput {
            data = try JSONSerialization.data(withJSONObject: input)
        } else if let fromText = ClaudeClient.extractJSON(from: stripComments(outcome.text)) {
            data = fromText   // fallback: the model answered in text instead of calling the tool
        } else {
            throw ImportError.decode("no schedule in the reply. Reply was: \(outcome.text.prefix(300))")
        }
        return try decode(data, vehicle: vehicle, usage: outcome.usage, model: model)
    }

    static func decode(_ data: Data, vehicle: VehicleDescription, usage: AIUsage, model: String) throws -> Result {
        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ImportError.decode(error.localizedDescription)
        }
        let template = ScheduleTemplate(
            id: "ai-\(UUID().uuidString)",
            make: env.make ?? vehicle.make,
            model: env.model ?? vehicle.model,
            aliases: nil,
            generation: env.generation,
            yearFrom: nil, yearTo: nil,
            kind: vehicle.kind, fuel: vehicle.fuel,
            source: L("AI import: %@", env.source ?? L("web search")),
            sourceURLs: env.sourceURLs,
            disclaimer: env.disclaimer ?? L("Extracted automatically by AI — double-check against your manual."),
            tasks: env.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty },
            specs: env.specs)
        return Result(template: template, manualURLs: env.manualURLs ?? [], summary: env.summary ?? "",
                      usage: usage, model: model)
    }

    /// Removes `// comments` a model may copy into JSON written as text (keeps URLs).
    static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            if let r = line.range(of: "//"), !line[..<r.lowerBound].contains("http") && !line[..<r.lowerBound].hasSuffix(":") {
                return String(line[..<r.lowerBound])
            }
            return String(line)
        }.joined(separator: "\n")
    }

    /// Downloads a PDF from a URL (used for the manual links Claude found).
    static func downloadPDF(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard data.prefix(5) == Data("%PDF-".utf8) else { throw URLError(.cannotDecodeContentData) }
        return data
    }
}
