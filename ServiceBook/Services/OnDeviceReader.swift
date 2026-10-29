import Foundation
import PDFKit
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who reads an uploaded manual or service booklet: Claude, Apple Intelligence, or a downloaded open model (MLX).
enum ManualReader: String {
    case claude, onDevice, mlx
}

/// Availability of Apple's on-device language model (Apple Intelligence, iOS 26+).
enum OnDeviceAI {
    /// nil when the on-device model can be used, otherwise a reason to show the user.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return L("This iPhone doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled): return L("Turn on Apple Intelligence in the iPhone's Settings to read the manual on this iPhone.")
            case .unavailable(.modelNotReady): return L("Apple Intelligence is still downloading its model. Try again later.")
            default: return L("Apple Intelligence is not available right now.")
            }
        }
        #endif
        return L("Reading on this iPhone needs iOS 26 and Apple Intelligence.")
    }

    static var isAvailable: Bool { unavailableReason == nil }
}

/// Text of manual pages: the PDF's own text layer, or OCR (Vision) for scans and photos.
enum PageText {
    static func pages(of data: Data, progress: (Int, Int) -> Void) throws -> [String] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var result: [String] = []
        for i in 0..<doc.pageCount {
            try Task.checkCancellation()
            progress(i + 1, doc.pageCount)
            guard let page = doc.page(at: i) else { result.append(""); continue }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
                result.append(text)
            } else {
                result.append(ocr(page))
            }
        }
        return result
    }

    static func ocr(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let k = 2000 / max(bounds.width, bounds.height)
        let image = page.thumbnail(of: CGSize(width: bounds.width * k, height: bounds.height * k), for: .mediaBox)
        guard let cg = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let items = (request.results ?? []).compactMap { o -> (box: CGRect, text: String)? in
            guard let t = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, t)
        }
        return lines(from: items)
    }

    /// Joins recognised text top to bottom, keeping the cells of a table row on one line
    /// (Vision boxes are normalised with the origin at the bottom left).
    static func lines(from items: [(box: CGRect, text: String)]) -> String {
        var rows: [[(box: CGRect, text: String)]] = []
        for item in items.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = rows.last?.first,
               abs(first.box.midY - item.box.midY) < min(first.box.height, item.box.height) / 2 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " | ") }
            .joined(separator: "\n")
    }

    /// Photos of the booklet pages as one PDF, downscaled so it stays light to store and send.
    static func pdf(fromPhotos photos: [Data], maxSide: CGFloat = 2000) -> Data? {
        let images = photos.compactMap(UIImage.init(data:)).map { image in
            let k = min(1, maxSide / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            // Redrawing also applies the photo's orientation.
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return AttachmentIO.pdf(from: images)
    }
}

/// Builds a maintenance schedule from a manual or service booklet with Apple's on-device model:
/// free, offline, and nothing leaves the iPhone. The model has a 4096-token window, so the
/// maintenance pages are read a few at a time and the items are merged afterwards.
enum OnDeviceImporter {
    enum ImportError: LocalizedError {
        case unavailable(String)
        case noText
        case language
        case background

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .noText: L("Could not find any maintenance pages in this document. Try clearer photos, or only the pages with the maintenance schedule.")
            case .language: L("Apple Intelligence can't read this language yet. Try reading with Claude instead.")
            case .background: L("Reading stopped because the app went to the background. Keep the app open while the iPhone reads.")
            }
        }
    }

    struct Chunk: Equatable {
        var pages: [Int]
        var text: String

        var label: String {
            guard let first = pages.first, let last = pages.last else { return "" }
            return first == last ? "\(first + 1)" : "\(first + 1)–\(last + 1)"
        }
    }

    static let specGroups = ["Fluids", "Tyres", "Torques", "Electrical", "Owner checks", "Notes"]

    static func importPDF(data: Data, vehicle: ManualImporter.VehicleDescription,
                          onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> ManualImporter.Result {
        if let reason = OnDeviceAI.unavailableReason { throw ImportError.unavailable(reason) }
        let pages = try PageText.pages(of: data) { i, n in
            onEvent(.status(L("Reading page %lld of %lld…", i, n)))
        }
        let chunks = chunks(from: pages)
        guard !chunks.isEmpty else { throw ImportError.noText }

        var items: [[String: Any]] = []
        var specs: [[String: Any]] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            for (n, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                onEvent(.status(L("Reading the maintenance pages on this iPhone (%lld of %lld)…", n + 1, chunks.count)))
                let found = try await extract(chunk.text, pages: chunk.label, vehicle: vehicle)
                items += found.items
                specs += found.specs
                onEvent(.writing(merge(items).count))
            }
        }
        #endif

        return try result(items: items, specs: specs, pages: chunks.flatMap(\.pages).count,
                          vehicle: vehicle, model: L("Apple Intelligence (on this iPhone)"))
    }

    /// Merged items in the `submit_schedule` JSON shape, decoded like a Claude result so the
    /// review screen is shared.
    static func result(items: [[String: Any]], specs: [[String: Any]], pages: Int,
                       vehicle: ManualImporter.VehicleDescription, model: String) throws -> ManualImporter.Result {
        let envelope: [String: Any] = [
            "make": vehicle.make,
            "model": vehicle.model,
            "source": L("your manual, read on this iPhone"),
            "summary": L("Read %lld pages on this iPhone. Nothing was sent online.", pages),
            "disclaimer": L("Extracted automatically on this iPhone — double-check every interval against your manual."),
            "tasks": merge(items),
            "specs": uniqueSpecs(specs),
        ]
        let json = try JSONSerialization.data(withJSONObject: envelope)
        return try ManualImporter.decode(json, vehicle: vehicle, usage: AIUsage(), model: model)
    }

    // MARK: Pages → chunks

    /// Short documents (a few photos or scans) are read whole; for a full manual only the
    /// pages about maintenance are kept. Pages are packed into chunks of about `size` characters.
    static func chunks(from pages: [String], size: Int = 3000, maxChunks: Int = 16) -> [Chunk] {
        let scores = pages.map { ManualImporter.score($0) }
        var indices = pages.indices.filter { !pages[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if indices.count > 6 {
            indices = Array(indices.filter { scores[$0] > 0 }
                .sorted { scores[$0] > scores[$1] }
                .prefix(maxChunks * 2))
                .sorted()
        }

        var result: [Chunk] = []
        for i in indices {
            for piece in split(pages[i], size: size) {
                let text = "[page \(i + 1)]\n" + piece
                if var last = result.last, last.text.count + text.count + 2 <= size {
                    last.text += "\n\n" + text
                    if last.pages.last != i { last.pages.append(i) }
                    result[result.count - 1] = last
                } else {
                    result.append(Chunk(pages: [i], text: text))
                }
            }
        }
        if result.count > maxChunks {
            let chunkScores = result.map { ManualImporter.score($0.text) }
            let best = result.indices.sorted { chunkScores[$0] > chunkScores[$1] }.prefix(maxChunks).sorted()
            result = best.map { result[$0] }
        }
        return result
    }

    /// Splits text at line breaks into pieces of at most `size` characters.
    static func split(_ text: String, size: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(line)
            while line.count > size {
                if !current.isEmpty { pieces.append(current); current = "" }
                pieces.append(String(line.prefix(size)))
                line = String(line.dropFirst(size))
            }
            if current.count + line.count + 1 > size, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: Merging

    /// The same item often appears on several pages: keep one per title and action, the most complete.
    static func merge(_ items: [[String: Any]]) -> [[String: Any]] {
        var order: [String] = []
        var best: [String: [String: Any]] = [:]
        for item in items {
            guard let title = item["title"] as? String else { continue }
            let key = title.lowercased().filter { $0.isLetter || $0.isNumber } + "|" + (item["action"] as? String ?? "")
            if let existing = best[key] {
                if item.count > existing.count { best[key] = item }
            } else {
                order.append(key)
                best[key] = item
            }
        }
        return order.compactMap { best[$0] }
    }

    static func uniqueSpecs(_ specs: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        return specs.filter { s in
            let key = ((s["title"] as? String ?? "") + "|" + (s["value"] as? String ?? "")).lowercased()
            return seen.insert(key).inserted
        }
    }

    // MARK: Model

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func extract(_ text: String, pages: String, vehicle: ManualImporter.VehicleDescription,
                                depth: Int = 0) async throws -> (items: [[String: Any]], specs: [[String: Any]]) {
        let instructions = """
        You read pages of a vehicle owner's manual or service booklet and list its periodic maintenance.
        - One item per component and action, e.g. "Engine oil" with action replace.
        - Copy intervals exactly. Use km: convert miles (1 mi = 1.609 km). Give km and months when both are given.
        - In a table with km or month columns, the interval is the step between two marks on that row.
        - Never invent numbers. Return no items when the pages have no maintenance information.
        - Write titles, notes and specification values in \(AppLanguage.englishName).
        """
        let prompt = """
        Vehicle: \(vehicle.text).

        \(text)

        List the maintenance items and specifications on these pages.
        """
        let session = LanguageModelSession(instructions: instructions)
        do {
            let page = try await session.respond(to: prompt, generating: BookletPage.self,
                                                 options: GenerationOptions(sampling: .greedy)).content
            let source = L("Manual p. %@", pages)
            return (page.items.compactMap { $0.dictionary(source: source) }, page.specs.map { $0.dictionary() })
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize where depth < 3 && text.count > 400:
                // Too long for the 4096-token window: read it in two halves.
                var items: [[String: Any]] = []
                var specs: [[String: Any]] = []
                for half in split(text, size: text.count / 2 + 1) {
                    let r = try await extract(half, pages: pages, vehicle: vehicle, depth: depth + 1)
                    items += r.items
                    specs += r.specs
                }
                return (items, specs)
            case .exceededContextWindowSize, .guardrailViolation, .decodingFailure:
                return ([], [])   // skip this part, keep the rest
            case .unsupportedLanguageOrLocale:
                throw ImportError.language
            case .rateLimited:
                throw ImportError.background
            default:
                throw error
            }
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct BookletPage {
    @Guide(description: "Periodic maintenance items on these pages", .maximumCount(25))
    var items: [BookletItem]
    @Guide(description: "Fluid grades and capacities, tyre pressures, torques, owner checks", .maximumCount(12))
    var specs: [BookletSpec]
}

@available(iOS 26.0, *)
@Generable
struct BookletItem {
    @Guide(description: "Component or check, e.g. Engine oil")
    var title: String
    @Guide(description: "What to do", .anyOf(ManualImporter.actions))
    var action: String
    @Guide(description: "Area of the vehicle", .anyOf(ManualImporter.categories))
    var category: String
    var everyKm: Int?
    var everyMonths: Int?
    @Guide(description: "First time in km when different from the interval, e.g. run-in service")
    var firstKm: Int?
    @Guide(description: "True when done only once")
    var onceOnly: Bool
    @Guide(description: "Short condition or warning from the manual")
    var note: String?

    /// The item in the JSON shape of `submit_schedule`; nil when it has no interval at all.
    func dictionary(source: String) -> [String: Any]? {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let km = everyKm.flatMap { $0 > 0 ? $0 : nil }
        let months = everyMonths.flatMap { $0 > 0 ? $0 : nil }
        let first = firstKm.flatMap { $0 > 0 ? $0 : nil }
        guard !title.isEmpty, km != nil || months != nil || first != nil else { return nil }
        var d: [String: Any] = ["title": title, "action": action, "category": category, "sourceRef": source]
        if onceOnly {
            d["oneTime"] = true
            if let k = first ?? km { d["firstKm"] = k }
            if let m = months { d["firstMonths"] = m }
        } else {
            if let km { d["intervalKm"] = km }
            if let months { d["intervalMonths"] = months }
            if let first, first != km { d["firstKm"] = first }
        }
        if let note = self.note, !note.trimmingCharacters(in: .whitespaces).isEmpty { d["notes"] = note }
        return d
    }
}

@available(iOS 26.0, *)
@Generable
struct BookletSpec {
    @Guide(description: "Group", .anyOf(OnDeviceImporter.specGroups))
    var group: String
    @Guide(description: "e.g. Engine oil")
    var title: String
    @Guide(description: "e.g. SAE 10W-40, 2.0 L")
    var value: String

    func dictionary() -> [String: Any] { ["group": group, "title": title, "value": value] }
}
#endif
