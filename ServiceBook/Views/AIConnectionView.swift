import SwiftUI

/// Settings → Claude connection: API key, connection test, model choice, search limits and usage.
struct AIConnectionView: View {
    enum Status: Equatable {
        case notSetUp, checking, connected(Int), failed(String)
    }

    @State private var keyInput = ""
    @State private var revealKey = false
    @State private var status: Status = .notSetUp
    @State private var models: [ModelInfo] = []
    @State private var selectedModel = AppSettings.model
    @State private var customModel = ""
    @State private var maxSearches = AppSettings.maxSearches
    @State private var useRegion = AppSettings.useRegion
    @State private var usage = AppSettings.totalUsage
    @State private var imports = AppSettings.importCount
    @State private var hasSavedKey = AppSettings.hasKey

    private var availableModels: [ModelInfo] {
        var list = models.isEmpty ? AppSettings.fallbackModels : models
        if !list.contains(where: { $0.id == selectedModel }) {
            list.append(ModelInfo(id: selectedModel, displayName: selectedModel))
        }
        return list
    }

    var body: some View {
        Form {
            Section {
                statusRow
                if hasSavedKey {
                    Button { Task { await test() } } label: { Label("Test connection", systemImage: "bolt.horizontal") }
                        .disabled(status == .checking)
                }
            }

            Section {
                HStack {
                    Group {
                        if revealKey {
                            TextField("sk-ant-…", text: $keyInput)
                        } else {
                            SecureField(hasSavedKey ? "•••••••• (saved)" : "sk-ant-…", text: $keyInput)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())
                    Button { revealKey.toggle() } label: { Image(systemName: revealKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(revealKey ? "Hide key" : "Show key")
                }
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        let s = (strings.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { @MainActor in keyInput = s }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    Spacer()
                    Button("Save & test") { Task { await saveAndTest() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !keyInput.isEmpty && !keyInput.hasPrefix("sk-ant-") {
                    Text("Claude API keys start with “sk-ant-”.").font(.caption).foregroundStyle(.orange)
                }
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("Create a key at console.anthropic.com", systemImage: "arrow.up.right.square")
                }
                if hasSavedKey {
                    Button("Remove key from this device", role: .destructive) {
                        Keychain.set(nil, for: AppSettings.apiKeyAccount)
                        UserDefaults.standard.set(false, forKey: AppSettings.connectionOKKey)
                        hasSavedKey = false
                        keyInput = ""
                        models = []
                        status = .notSetUp
                    }
                }
            } header: {
                Text("API key")
            } footer: {
                Text("Stored in this device's Keychain only (not synced to iCloud) and sent only to api.anthropic.com. You pay Anthropic directly for what you use; set a monthly limit in the console if you like.")
            }

            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels) { m in
                        Text(m.displayName).tag(m.id)
                    }
                }
                .onChange(of: selectedModel) { _, id in saveModel(id) }
                if let m = availableModels.first(where: { $0.id == selectedModel }) {
                    if m.supportsWebSearch == false {
                        Label("This model can't search the web — “Find the manual online” won't work with it.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(modelHint(m.id)).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Custom model ID") {
                    HStack {
                        TextField("e.g. claude-sonnet-5-5", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button("Use") {
                            let id = customModel.trimmingCharacters(in: .whitespaces)
                            guard !id.isEmpty else { return }
                            selectedModel = id
                            saveModel(id)
                        }
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text(models.isEmpty ? "Test the connection to load the models your key can use." : "\(models.count) models available to your key.")
            }

            Section {
                Stepper("Up to \(maxSearches) web searches", value: $maxSearches, in: 3...15)
                    .onChange(of: maxSearches) { _, n in UserDefaults.standard.set(n, forKey: AppSettings.maxSearchesKey) }
                Toggle(isOn: $useRegion) {
                    VStack(alignment: .leading) {
                        Text("Prefer my country's schedule")
                        if let code = AppSettings.regionCode {
                            Text(Locale.current.localizedString(forRegionCode: code) ?? code).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: useRegion) { _, on in UserDefaults.standard.set(on, forKey: AppSettings.useRegionKey) }
            } header: {
                Text("Finding manuals online")
            } footer: {
                Text("More searches find obscure manuals more often but cost more. Service intervals can differ by market (e.g. Europe vs. US), so your country is shared with the search.")
            }

            Section {
                LabeledContent("Imports", value: "\(imports)")
                LabeledContent("Input tokens", value: Fmt.number.string(from: NSNumber(value: usage.inputTokens)) ?? "0")
                LabeledContent("Output tokens", value: Fmt.number.string(from: NSNumber(value: usage.outputTokens)) ?? "0")
                LabeledContent("Web searches", value: "\(usage.webSearches)")
                LabeledContent("Pages read", value: "\(usage.webFetches)")
                Button("Reset counters") {
                    AppSettings.resetUsage()
                    usage = AIUsage()
                    imports = 0
                }
            } header: {
                Text("Usage on this device")
            } footer: {
                Text("Exact costs are shown in the Anthropic console.")
            }
        }
        .navigationTitle("Claude connection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if hasSavedKey {
                status = UserDefaults.standard.bool(forKey: AppSettings.connectionOKKey) ? .connected(0) : .notSetUp
                await test()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .notSetUp:
            Label(hasSavedKey ? "Not tested yet" : "Not set up — add your API key below", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView(); Text("Checking connection…").foregroundStyle(.secondary) }
        case .connected(let n):
            Label(n > 0 ? "Connected · \(n) models available" : "Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func modelHint(_ id: String) -> String {
        if id.contains("opus") || id.contains("fable") || id.contains("mythos") { return "Most thorough. Best for hard-to-find manuals, highest cost." }
        if id.contains("haiku") { return "Fastest and cheapest. Fine for clean PDFs, weaker at finding manuals online." }
        if id.contains("sonnet") { return "Recommended: good balance of accuracy, speed and cost." }
        return "Custom model."
    }

    private func saveModel(_ id: String) {
        UserDefaults.standard.set(id, forKey: AppSettings.modelKey)
        let limit = availableModels.first(where: { $0.id == id })?.maxTokens ?? 0
        UserDefaults.standard.set(limit, forKey: AppSettings.modelMaxTokensKey)
    }

    private func saveAndTest() async {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(key, for: AppSettings.apiKeyAccount)
        hasSavedKey = AppSettings.hasKey
        keyInput = ""
        revealKey = false
        await test()
    }

    private func test() async {
        guard let client = AppSettings.client else { status = .notSetUp; return }
        status = .checking
        do {
            let list = try await client.listModels()
            models = list.sorted { a, b in
                // Web-search capable models first, then by name.
                let wa = a.supportsWebSearch ?? true, wb = b.supportsWebSearch ?? true
                return wa != wb ? wa : a.displayName < b.displayName
            }
            status = .connected(list.count)
            UserDefaults.standard.set(true, forKey: AppSettings.connectionOKKey)
            if let m = models.first(where: { $0.id == selectedModel }) {
                UserDefaults.standard.set(m.maxTokens ?? 0, forKey: AppSettings.modelMaxTokensKey)
            }
        } catch {
            status = .failed(error.localizedDescription)
            UserDefaults.standard.set(false, forKey: AppSettings.connectionOKKey)
        }
    }
}
