import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import VisionKit

/// AI import: finds the owner's manual online, or reads a manual / service booklet the user
/// uploads (PDF, photos or scan) with Claude or on the iPhone, and lets the user review the
/// extracted schedule before adding it to the vehicle.
struct ManualImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State var mode: ImportMode

    enum Phase {
        case idle
        case working
        case review(ManualImporter.Result)
        case failed(String)
    }

    /// One line of the live activity feed.
    struct Activity: Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    @State private var phase: Phase = .idle
    @State private var activity: [Activity] = []
    @State private var status = ""
    @State private var writing: Int?
    @State private var searches = 0
    @State private var pages = 0
    @State private var started = Date()
    @State private var job: Task<Void, Never>?
    @State private var showImporter = false
    @State private var showConnection = false
    @State private var hasKey = AppSettings.hasKey
    @State private var selected: Set<Int> = []
    @State private var replace = true
    @State private var savedPDFs: Set<String> = []
    @State private var downloading: String?
    @State private var pickedFile: PendingAttachment?
    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @AppStorage("manualReader") private var reader: ManualReader = .claude

    private var localReason: String? { OnDeviceAI.unavailableReason }
    @State private var showModel = false
    @State private var modelReady = LocalModel.ready
    private var readsOnDevice: Bool { mode == .pdf && reader != .claude }
    private var canRead: Bool {
        switch reader {
        case .claude: hasKey
        case .onDevice: localReason == nil
        case .mlx: modelReady != nil
        }
    }

    private var vehicleDescription: ManualImporter.VehicleDescription {
        .init(make: vehicle.make, model: vehicle.modelName, year: vehicle.year,
              variant: vehicle.variant, fuel: vehicle.fuel.rawValue, kind: vehicle.kind.rawValue)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle: idleView
                case .working: workingView
                case .review(let result): reviewView(result)
                case .failed(let message): failedView(message)
                }
            }
            .navigationTitle(mode == .online ? "Find the manual" : "Upload the manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isWorking {
                        Button("Stop", role: .destructive) { cancel() }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result, let file = AttachmentIO.read(url) else { return }
                pickedFile = file
                runPDF(file.data)
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { data in
                    showScanner = false
                    if let data { use(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var photos: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { photos.append(data) }
                    }
                    photoItems = []
                    if let pdf = PageText.pdf(fromPhotos: photos) { use(pdf) }
                }
            }
            .onAppear {
                // First time: without a Claude key, read on the iPhone when Apple Intelligence is there.
                if UserDefaults.standard.object(forKey: "manualReader") == nil, !hasKey {
                    if OnDeviceAI.isAvailable { reader = .onDevice } else if LocalModel.ready != nil { reader = .mlx }
                }
            }
            .sheet(isPresented: $showModel, onDismiss: { modelReady = LocalModel.ready }) {
                NavigationStack {
                    LocalModelView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showModel = false } }
                        }
                }
            }
            .sheet(isPresented: $showConnection, onDismiss: { hasKey = AppSettings.hasKey }) {
                NavigationStack {
                    AIConnectionView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showConnection = false } }
                        }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    // MARK: Phases

    private var idleView: some View {
        Form {
            Section {
                Label(vehicle.displayName + (vehicle.year > 0 ? " (\(vehicle.year))" : ""), systemImage: vehicle.kind.symbol)
                    .font(.headline)
                if !vehicle.variant.isEmpty { Text(vehicle.variant).foregroundStyle(.secondary) }
            } footer: {
                Text("Tip: the more precise the model, year and engine, the better the result. Edit the vehicle first if needed.")
            }

            if mode == .online || reader == .claude {
                Section {
                    if hasKey {
                        LabeledContent("Model", value: AppSettings.model)
                        Button("Change connection settings") { showConnection = true }
                    } else {
                        Text("AI import uses Claude with your own API key. Set it up once — it stays in this device's Keychain.")
                        Button {
                            showConnection = true
                        } label: {
                            Label("Set up Claude connection", systemImage: "sparkles")
                        }
                    }
                }
            }

            Picker("Source", selection: $mode) {
                Text("Search online").tag(ImportMode.online)
                Text("Upload").tag(ImportMode.pdf)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if mode == .online {
                Section {
                    Text("Claude searches the web for the official owner's manual or maintenance schedule, reads it, and turns every check into an item with its interval in km and months, plus important notes and specifications.")
                        .font(.callout)
                    Button {
                        runOnline()
                    } label: {
                        Label("Search for the manual", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(!hasKey)
                } footer: {
                    Text("Takes one to three minutes, with up to \(AppSettings.maxSearches) web searches. Uses your Claude API credits (typically a few cents).")
                }
            } else {
                Section {
                    Picker("Read with", selection: $reader) {
                        Text("Claude").tag(ManualReader.claude)
                        Text("Apple Intelligence").tag(ManualReader.onDevice)
                        Text("Open model (on this iPhone)").tag(ManualReader.mlx)
                    }
                    if reader == .mlx {
                        if let modelReady {
                            Text("\(modelReady.name) reads the pages on this iPhone: free, works offline and in every country, nothing leaves the device. Claude is more accurate on large maintenance tables.")
                                .font(.callout)
                        } else {
                            Text("Download a free open model once (about 1 GB) to read manuals on this iPhone, without Apple Intelligence.")
                                .font(.callout)
                        }
                        Button(modelReady == nil ? "Download the model…" : "Change model…") { showModel = true }
                    }
                    if reader == .onDevice {
                        if let localReason {
                            Label(localReason, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Apple Intelligence reads the pages on this iPhone: free, works offline, and nothing leaves the device. Claude is more accurate on large maintenance tables.")
                                .font(.callout)
                        }
                    }
                }

                Section {
                    Text("Upload the owner's manual or the service booklet: a PDF, photos of the pages, or a scan. The app picks the maintenance pages and turns them into your schedule.")
                        .font(.callout)
                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose a PDF…", systemImage: "doc.badge.plus")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                        Label("Choose photos of the pages…", systemImage: "photo.on.rectangle")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan the booklet…", systemImage: "doc.viewfinder")
                        }
                    }
                    let manuals = vehicle.documents.filter(\.isPDF)
                    ForEach(manuals) { doc in
                        Button {
                            runPDF(doc.data)
                        } label: {
                            Label("Use “\(doc.displayName)”", systemImage: "doc.richtext")
                        }
                    }
                } footer: {
                    Text(reader != .claude
                         ? "Tip: photograph or scan only the maintenance pages — the iPhone reads up to about 30 pages and can take a few minutes. A copy is saved in the vehicle's documents."
                         : "A copy of the PDF is saved in the vehicle's documents.")
                }
                .disabled(!canRead)
            }
        }
    }

    private var workingView: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.isEmpty ? L("Working…") : status).font(.headline)
                        TimelineView(.periodic(from: started, by: 1)) { ctx in
                            let s = Int(ctx.date.timeIntervalSince(started))
                            Text(String(format: "%d:%02d", s / 60, s % 60) + statsText)
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                if let n = writing {
                    ProgressView(value: Double(min(n, 40)), total: 40) {
                        Text(L("Writing the schedule — %lld items", n)).font(.caption)
                    }
                }
            }
            if !activity.isEmpty {
                Section("Activity") {
                    ForEach(activity.reversed()) { a in
                        Label {
                            Text(a.text).font(.caption).lineLimit(2)
                        } icon: {
                            Image(systemName: a.symbol).foregroundStyle(.tint)
                        }
                    }
                }
            }
            Section {
                Button("Stop", role: .destructive) { cancel() }
            } footer: {
                Text(readsOnDevice
                     ? "Keep the app open while the iPhone reads — nothing is added until you review the result."
                     : "You can keep the app open while Claude reads — nothing is added until you review the result.")
            }
        }
    }

    private var statsText: String {
        var parts: [String] = []
        if searches > 0 { parts.append(L("%lld searches", searches)) }
        if pages > 0 { parts.append(L("%lld pages read", pages)) }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Import failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { phase = .idle }
                .buttonStyle(.borderedProminent)
        }
    }

    private func reviewView(_ result: ManualImporter.Result) -> some View {
        let tasks = result.template.tasks
        return List {
            Section {
                if !result.summary.isEmpty { Text(result.summary).font(.callout) }
                if let d = result.template.disclaimer { Text(d).font(.footnote).foregroundStyle(.secondary) }
                Label(result.usage == AIUsage() ? result.model : "\(result.model) · \(result.usage.summary)",
                      systemImage: result.usage == AIUsage() ? "iphone" : "gauge.with.dots.needle.33percent")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(result.template.sourceURLs ?? [], id: \.self) { s in
                    if let url = URL(string: s) {
                        Link(url.host() ?? s, destination: url).font(.footnote)
                    }
                }
            } header: {
                Text("Found: \(result.template.make) \(result.template.model) \(result.template.generation ?? "")")
            }

            let pdfs = result.manualURLs.filter { $0.lowercased().contains(".pdf") || $0.lowercased().contains("pdf") }
            if !pdfs.isEmpty {
                Section("Manual PDFs") {
                    ForEach(pdfs, id: \.self) { s in
                        HStack {
                            Text(URL(string: s)?.lastPathComponent ?? s).font(.footnote).lineLimit(2)
                            Spacer()
                            if savedPDFs.contains(s) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if downloading == s {
                                ProgressView()
                            } else {
                                Button("Save") { download(s) }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            if !vehicle.tasks.isEmpty {
                Section {
                    Toggle("Replace current schedule", isOn: $replace)
                } footer: {
                    Text(replace ? "Items you created yourself and items with history are kept."
                                 : "Only items with a new name are added.")
                }
            }

            Section {
                ForEach(Array(tasks.enumerated()), id: \.offset) { i, t in
                    Button {
                        if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(i) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).foregroundStyle(.primary)
                                Text("\((TaskAction(rawValue: t.actionRaw ?? "") ?? .inspect).label) · \(t.intervalText)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let n = t.notes, !n.isEmpty {
                                    Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(selected.count) of \(tasks.count) items")
                    Spacer()
                    Button(selected.count == tasks.count ? "None" : "All") {
                        selected = selected.count == tasks.count ? [] : Set(tasks.indices)
                    }
                    .font(.caption)
                }
            }

            if let specs = result.template.specs, !specs.isEmpty {
                Section("Specifications (\(specs.count))") {
                    ForEach(Array(specs.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading) {
                            Text(s.title).font(.caption).foregroundStyle(.secondary)
                            Text(s.value).font(.callout)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                apply(result)
            } label: {
                Text("Add \(selected.count) items to \(vehicle.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty)
            .padding()
            .background(.bar)
        }
    }

    // MARK: Actions

    private func runOnline() {
        let desc = vehicleDescription
        start { onEvent in
            try await ManualImporter().searchOnline(for: desc, onEvent: onEvent)
        }
    }

    private func runPDF(_ data: Data) {
        let desc = vehicleDescription
        switch reader {
        case .onDevice:
            start { onEvent in
                try await OnDeviceImporter.importPDF(data: data, vehicle: desc, onEvent: onEvent)
            }
        case .mlx:
            start { onEvent in
                try await MLXImporter.importPDF(data: data, vehicle: desc, onEvent: onEvent)
            }
        case .claude:
            start { onEvent in
                try await ManualImporter().importPDF(data: data, vehicle: desc, onEvent: onEvent)
            }
        }
    }

    /// Photos or a scan of the booklet, combined into one PDF: read it and keep a copy.
    private func use(_ pdf: Data) {
        pickedFile = PendingAttachment(filename: L("Service booklet %@.pdf", Fmt.date(Date())),
                                       typeIdentifier: UTType.pdf.identifier, data: pdf)
        runPDF(pdf)
    }

    private func start(_ work: @escaping (@escaping @Sendable (AIEvent) -> Void) async throws -> ManualImporter.Result) {
        activity = []
        status = ""
        writing = nil
        searches = 0
        pages = 0
        started = Date()
        phase = .working
        job = Task {
            do {
                let result = try await work { event in
                    Task { @MainActor in handle(event) }
                }
                await MainActor.run {
                    if result.usage != AIUsage() { AppSettings.record(result.usage) }
                    show(result)
                }
            } catch is CancellationError {
                await MainActor.run { phase = .idle }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled { phase = .failed(error.localizedDescription) }
                }
            }
        }
    }

    private func cancel() {
        job?.cancel()
        job = nil
        phase = .idle
    }

    @MainActor
    private func handle(_ event: AIEvent) {
        guard isWorking else { return }
        switch event {
        case .status(let s):
            status = s
        case .searching(let q):
            searches += 1
            status = L("Searching the web…")
            activity.append(Activity(symbol: "magnifyingglass", text: q))
        case .reading(let u):
            pages += 1
            status = L("Reading a page…")
            let url = URL(string: u)
            activity.append(Activity(symbol: u.lowercased().contains(".pdf") ? "doc.richtext" : "doc.text",
                                     text: (url?.host() ?? u) + (url.map { $0.path.count > 1 ? $0.path : "" } ?? "")))
        case .results(let n):
            activity.append(Activity(symbol: "list.bullet", text: L("%lld results", n)))
        case .writing(let n):
            status = L("Writing the schedule…")
            writing = n
        case .retrying(let seconds, let reason):
            status = L("Retrying in %lld s…", seconds)
            activity.append(Activity(symbol: "arrow.clockwise", text: reason))
        }
    }

    private func show(_ result: ManualImporter.Result) {
        if result.template.tasks.isEmpty {
            phase = .failed(L("No maintenance items were found. Try a more precise model description, or import the manual PDF."))
            return
        }
        selected = Set(result.template.tasks.indices)
        phase = .review(result)
    }

    private func download(_ s: String) {
        downloading = s
        Task {
            do {
                let data = try await ManualImporter.downloadPDF(s)
                await MainActor.run {
                    let name = URL(string: s)?.lastPathComponent ?? "Manual.pdf"
                    let a = Attachment(filename: name.lowercased().hasSuffix(".pdf") ? name : name + ".pdf",
                                       typeIdentifier: UTType.pdf.identifier, data: data, label: L("Owner's manual"))
                    context.insert(a)
                    a.vehicle = vehicle
                    savedPDFs.insert(s)
                    downloading = nil
                }
            } catch {
                await MainActor.run { downloading = nil }
            }
        }
    }

    private func apply(_ result: ManualImporter.Result) {
        let chosen = result.template.tasks.enumerated().filter { selected.contains($0.offset) }.map(\.element)
        ScheduleApplier.apply(result.template, tasks: chosen, to: vehicle, in: context,
                              replace: replace && !vehicle.tasks.isEmpty)
        if let file = pickedFile, !vehicle.documents.contains(where: { $0.data.count == file.data.count && $0.filename == file.filename }) {
            let a = Attachment(filename: file.filename, typeIdentifier: UTType.pdf.identifier, data: file.data, label: L("Owner's manual"))
            context.insert(a)
            a.vehicle = vehicle
        }
        try? context.save()
        ReminderScheduler.reschedule(context: context)
        dismiss()
    }
}
