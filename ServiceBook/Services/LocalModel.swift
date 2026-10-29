import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Open models downloaded once from Hugging Face and run on the iPhone with Apple's MLX.
/// Unlike Apple Intelligence they work on any recent iPhone and in every country.
enum LocalModel: String, CaseIterable, Identifiable {
    // Smallest first. Every id must have a configuration in mlx-swift-lm's LLMRegistry.
    case tiny = "mlx-community/Qwen3-0.6B-4bit"
    case lfm2 = "mlx-community/LFM2-1.2B-4bit"
    case llama = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    case small = "mlx-community/Qwen3-1.7B-4bit"
    case qwen35 = "mlx-community/Qwen3.5-2B-4bit"
    case large = "mlx-community/Qwen3-4B-4bit"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tiny: "Qwen3 0.6B"
        case .lfm2: "LFM2 1.2B"
        case .llama: "Llama 3.2 1B"
        case .small: "Qwen3 1.7B"
        case .qwen35: "Qwen3.5 2B"
        case .large: "Qwen3 4B"
        }
    }

    /// Download size (weights, tokenizer and chat template).
    var bytes: Int64 {
        switch self {
        case .tiny: 350_000_000
        case .lfm2: 663_000_000
        case .llama: 713_000_000
        case .small: 980_000_000
        case .qwen35: 1_750_000_000
        case .large: 2_280_000_000
        }
    }

    var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var detail: String {
        switch self {
        case .tiny: L("Smallest and fastest, for older iPhones. Finds fewer items.")
        case .lfm2: L("Small and quick, designed by Liquid AI for phones.")
        case .llama: L("Small, by Meta. Good with manuals in several languages.")
        case .small: L("Fast, works on most iPhones.")
        case .qwen35: L("Newer generation, a good balance of speed and accuracy. Needs an iPhone with 6 GB of memory (iPhone 13 Pro, iPhone 14 or later).")
        case .large: L("More accurate. Needs an iPhone with 8 GB of memory (iPhone 15 Pro or later).")
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .tiny: LLMRegistry.qwen3_0_6b_4bit
        case .lfm2: LLMRegistry.lfm2_1_2b_4bit
        case .llama: LLMRegistry.llama3_2_1B_4bit
        case .small: LLMRegistry.qwen3_1_7b_4bit
        case .qwen35: LLMRegistry.qwen3_5_2b_4bit
        case .large: LLMRegistry.qwen3_4b_4bit
        }
    }

    static let selectedKey = "localModel"
    static let patterns = ["*.safetensors", "*.json", "*.jinja"]

    static var selected: LocalModel {
        LocalModel(rawValue: UserDefaults.standard.string(forKey: selectedKey) ?? "") ?? .small
    }

    /// The chosen model if it is on the device, otherwise any downloaded one.
    static var ready: LocalModel? { ([selected] + allCases).first(where: \.isDownloaded) }

    /// Application Support/Models, kept out of iCloud backups (it can be downloaded again).
    static var storage: URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    private var readyKey: String { "localModelReady." + rawValue }
    private var repo: Repo.ID { Repo.ID(rawValue: rawValue)! }
    private var directory: URL { HubCache(cacheDirectory: Self.storage).repoDirectory(repo: repo, kind: .model) }

    var isDownloaded: Bool {
        UserDefaults.standard.bool(forKey: readyKey) && FileManager.default.fileExists(atPath: directory.path)
    }

    /// Downloads the weights and tokenizer. `progress` receives 0…1 on the main actor.
    func download(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        _ = try await HubClient(cache: HubCache(cacheDirectory: Self.storage))
            .downloadSnapshot(of: repo, matching: Self.patterns, progressHandler: { p in progress(p.fractionCompleted) })
        UserDefaults.standard.set(true, forKey: readyKey)
    }

    func delete() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removeObject(forKey: readyKey)
    }

    /// Loads the downloaded model into memory (a few seconds; no network).
    func load() async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(
            from: HubBridge(client: HubClient(cache: HubCache(cacheDirectory: Self.storage))),
            using: TransformersLoader(),
            configuration: configuration)
    }
}

/// Reads a manual with a downloaded open model. Same pipeline as Apple Intelligence (pages → chunks
/// → items merged), but the model writes JSON and the context is larger, so chunks are bigger.
enum MLXImporter {
    static func importPDF(data: Data, vehicle: ManualImporter.VehicleDescription,
                          onEvent: @escaping @Sendable (AIEvent) -> Void) async throws -> ManualImporter.Result {
        guard let model = LocalModel.ready else {
            throw OnDeviceImporter.ImportError.unavailable(L("Download the on-device model first."))
        }
        let pages = try PageText.pages(of: data) { i, n in
            onEvent(.status(L("Reading page %lld of %lld…", i, n)))
        }
        let chunks = OnDeviceImporter.chunks(from: pages, size: 6000, maxChunks: 8)
        guard !chunks.isEmpty else { throw OnDeviceImporter.ImportError.noText }

        onEvent(.status(L("Loading %@…", model.name)))
        let container = try await model.load()
        let instructions = Self.instructions
        var items: [[String: Any]] = []
        var specs: [[String: Any]] = []
        for (n, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onEvent(.status(L("Reading the maintenance pages on this iPhone (%lld of %lld)…", n + 1, chunks.count)))
            let session = ChatSession(container, instructions: instructions,
                                      generateParameters: GenerateParameters(maxTokens: 2500, temperature: 0),
                                      additionalContext: ["enable_thinking": false])
            let reply = try await session.respond(to: "Vehicle: \(vehicle.text).\n\n\(chunk.text)\n\nReply with the JSON object only.")
            let found = parse(reply, source: L("Manual p. %@", chunk.label))
            items += found.items
            specs += found.specs
            onEvent(.writing(OnDeviceImporter.merge(items).count))
        }
        return try OnDeviceImporter.result(items: items, specs: specs, pages: chunks.flatMap(\.pages).count,
                                           vehicle: vehicle, model: L("%@ (on this iPhone)", model.name))
    }

    /// Items and specs from the model's reply. Tolerates a `<think>` block or text around the JSON.
    static func parse(_ reply: String, source: String) -> (items: [[String: Any]], specs: [[String: Any]]) {
        var text = reply
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        guard let data = ClaudeClient.extractJSON(from: ManualImporter.stripComments(text)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        let items = (object["tasks"] as? [[String: Any]] ?? []).compactMap { item -> [String: Any]? in
            var item = item
            let hasInterval = ["intervalKm", "intervalMonths", "firstKm", "firstMonths"].contains { number(item[$0]) > 0 }
            guard let title = item["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty,
                  hasInterval else { return nil }
            item["sourceRef"] = source
            return item
        }
        let specs = (object["specs"] as? [[String: Any]] ?? []).filter { $0["title"] is String && $0["value"] is String }
        return (items, specs)
    }

    private static func number(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s.filter(\.isNumber)) ?? 0 }
        return 0
    }

    static var instructions: String { """
    You convert pages of a vehicle owner's manual or service booklet into a maintenance schedule.
    Reply with one JSON object and nothing else:
    {"tasks":[{"title":"Engine oil","action":"replace","category":"oil","intervalKm":12000,"intervalMonths":12,"notes":"..."}],
     "specs":[{"group":"Fluids","title":"Engine oil","value":"SAE 10W-40, 2.0 L"}]}
    Rules:
    - One task per component and action. action is one of: \(ManualImporter.actions.joined(separator: ", ")).
    - category is one of: \(ManualImporter.categories.joined(separator: ", ")).
    - intervalKm and intervalMonths are the repeat interval. In a chart with km columns, the interval is \
    the distance between two marks on the row (marks at 12, 24, 36 thousand km → 12000). Add firstKm only \
    when the first time differs (e.g. a mark at 1 thousand km for run-in). Use "oneTime": true for items done only once.
    - Use kilometres (1 mile = 1.609 km). Leave out a field rather than guess. Never invent numbers.
    - specs: fluid grades and capacities, tyre pressures, torques. group is one of: \
    \(OnDeviceImporter.specGroups.joined(separator: ", ")).
    - If the pages contain no maintenance information, reply {"tasks":[],"specs":[]}.
    - Write titles, notes and spec values in \(AppLanguage.englishName).
    """ }
}

// MARK: - Hugging Face bridges (what mlx-swift-lm's MLXHuggingFace macros expand to)

private struct HubBridge: MLXLMCommon.Downloader {
    let client: HubClient

    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        guard let repo = Repo.ID(rawValue: id) else { throw URLError(.badURL) }
        // Once downloaded, load offline from the local copy.
        let local = !useLatest && LocalModel(rawValue: id)?.isDownloaded == true
        return try await client.downloadSnapshot(of: repo, revision: revision ?? "main", matching: patterns,
                                                 localFilesOnly: local,
                                                 progressHandler: { @MainActor progress in progressHandler(progress) })
    }
}

private struct TransformersLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
