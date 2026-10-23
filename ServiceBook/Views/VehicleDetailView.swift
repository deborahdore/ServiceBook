import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct VehicleDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var vehicle: Vehicle

    enum Tab: String, CaseIterable, Identifiable {
        case schedule = "Schedule", history = "History", info = "Info"
        var id: String { rawValue }
    }

    enum SheetKind: Identifiable {
        case log(MaintenanceTask?, RecordKind)
        case mileage, addTask, edit, builtIn
        case importAI(ImportMode)

        var id: String {
            switch self {
            case .log(let t, let k): "log-\(t?.id.uuidString ?? "")-\(k.rawValue)"
            case .mileage: "mileage"
            case .addTask: "addTask"
            case .edit: "edit"
            case .builtIn: "builtIn"
            case .importAI(let m): "ai-\(m.rawValue)"
            }
        }
    }

    @State private var tab: Tab = .schedule
    @State private var sheet: SheetKind?
    @State private var showDocImporter = false
    @State private var previewURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                header
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            switch tab {
            case .schedule: scheduleSections
            case .history: historySections
            case .info: infoSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MaintenanceTask.self) { TaskDetailView(task: $0) }
        .navigationDestination(for: ServiceRecord.self) { RecordDetailView(record: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { addMenu }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .log(let task, let recordKind):
                LogServiceView(vehicle: vehicle, preselected: task.map { [$0] } ?? [], initialKind: recordKind)
            case .mileage:
                MileageView(vehicle: vehicle)
            case .addTask:
                TaskEditView(vehicle: vehicle, task: nil)
            case .edit:
                EditVehicleView(vehicle: vehicle)
            case .builtIn:
                BuiltInSchedulePicker(vehicle: vehicle)
            case .importAI(let mode):
                ManualImportView(vehicle: vehicle, mode: mode)
            }
        }
        .fileImporter(isPresented: $showDocImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard let p = AttachmentIO.read(url) else { continue }
                let a = Attachment(filename: p.filename, typeIdentifier: p.typeIdentifier, data: p.data)
                context.insert(a)
                a.vehicle = vehicle
            }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Delete \(vehicle.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete vehicle and all its records", role: .destructive) {
                context.delete(vehicle)
                try? context.save()
                ReminderScheduler.reschedule(context: context)
                dismiss()
            }
        } message: {
            Text("This removes the schedule, history, mileage log and all saved documents.")
        }
        .onChange(of: sheet == nil) { _, closed in
            if closed { ReminderScheduler.reschedule(context: context) }
        }
    }

    // MARK: Header

    private var header: some View {
        let counts = vehicle.statusCounts()
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: vehicle.kind.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.km(vehicle.currentKm)).font(.title2.weight(.semibold)).monospacedDigit()
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if counts.overdue > 0 { Text("\(counts.overdue) overdue").foregroundStyle(.red) }
                    if counts.soon > 0 { Text("\(counts.soon) due soon").foregroundStyle(.orange) }
                }
                .font(.caption.weight(.medium))
            }
            Spacer()
            Button { sheet = .mileage } label: {
                Label("Mileage", systemImage: "gauge.with.dots.needle.67percent")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Update mileage")
        }
        .padding(.vertical, 4)
    }

    private var addMenu: some View {
        Menu {
            Button { sheet = .log(nil, .service) } label: { Label("Log a service", systemImage: "wrench.and.screwdriver") }
            Button { sheet = .log(nil, .tyres) } label: { Label("Record a tyre change", systemImage: "circle.circle") }
            Button { sheet = .log(nil, .part) } label: { Label("Record a part replacement", systemImage: "gearshape.2") }
            Button { sheet = .mileage } label: { Label("Update mileage", systemImage: "gauge.with.dots.needle.67percent") }
            Divider()
            Button { sheet = .addTask } label: { Label("Add maintenance item", systemImage: "plus.circle") }
            Menu {
                Button { sheet = .importAI(.online) } label: { Label("Find the manual online (AI)", systemImage: "sparkle.magnifyingglass") }
                Button { sheet = .importAI(.pdf) } label: { Label("Import a manual PDF (AI)", systemImage: "doc.viewfinder") }
                Button { sheet = .builtIn } label: { Label("Built-in schedules", systemImage: "books.vertical") }
            } label: {
                Label("Load schedule", systemImage: "list.bullet.clipboard")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add")
    }

    // MARK: Schedule

    @ViewBuilder
    private var scheduleSections: some View {
        let rows = vehicle.scheduleRows()
        if rows.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No maintenance items", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Load the schedule from the owner's manual, or add your own items.")
                } actions: {
                    Button("Find the manual online (AI)") { sheet = .importAI(.online) }
                    Button("Import a manual PDF (AI)") { sheet = .importAI(.pdf) }
                    Button("Built-in schedules") { sheet = .builtIn }
                    Button("Add an item") { sheet = .addTask }
                }
            }
        } else {
            ForEach(DueStatus.allCases, id: \.self) { status in
                let group = rows.filter { $0.info.status == status }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { row in
                            NavigationLink(value: row.task) {
                                TaskRow(task: row.task, info: row.info)
                            }
                            .swipeActions(edge: .leading) {
                                Button { sheet = .log(row.task, .service) } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        Text("\(status.label) (\(group.count))")
                    }
                }
            }
            if !vehicle.scheduleDisclaimer.isEmpty {
                Section {
                    Text(vehicle.scheduleDisclaimer).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySections: some View {
        let records = vehicle.records.sorted { $0.date > $1.date }
        if records.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Log services, tyre changes and repairs, and attach the receipts.")
                } actions: {
                    Button("Log a service") { sheet = .log(nil, .service) }
                }
            }
        } else {
            let total = records.compactMap(\.cost).reduce(0, +)
            Section {
                ForEach(records) { record in
                    NavigationLink(value: record) { RecordRow(record: record) }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(records[i]) }
                }
            } header: {
                Text("\(records.count) entries")
            } footer: {
                if total > 0, let code = records.first?.currencyCode {
                    Text("Total spent: \(Fmt.money(total, code: code))")
                }
            }
        }
    }

    // MARK: Info

    @ViewBuilder
    private var infoSections: some View {
        Section("Details") {
            LabeledContent("Make", value: vehicle.make)
            LabeledContent("Model", value: vehicle.modelName)
            if vehicle.year > 0 { LabeledContent("Model year", value: String(vehicle.year)) }
            if !vehicle.variant.isEmpty { LabeledContent("Engine / version", value: vehicle.variant) }
            LabeledContent("Fuel", value: vehicle.fuel.label)
            if !vehicle.plate.isEmpty { LabeledContent("Plate", value: vehicle.plate) }
            if !vehicle.vin.isEmpty {
                LabeledContent("VIN", value: vehicle.vin).textSelection(.enabled)
            }
            if let reg = vehicle.firstRegistration { LabeledContent("First registration", value: Fmt.date(reg)) }
            if let b = vehicle.baselineKm {
                LabeledContent("Tracking since", value: "\(Fmt.km(b))" + (vehicle.baselineDate.map { " · \(Fmt.date($0))" } ?? ""))
            }
            if !vehicle.notes.isEmpty { Text(vehicle.notes).font(.callout) }
            Button("Edit vehicle") { sheet = .edit }
        }

        let groups = Dictionary(grouping: vehicle.specs, by: \.group)
        ForEach(groups.keys.sorted(), id: \.self) { g in
            Section(g) {
                ForEach((groups[g] ?? []).sorted { $0.sortOrder < $1.sortOrder }) { spec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.title).font(.caption).foregroundStyle(.secondary)
                        Text(spec.value).font(.callout).textSelection(.enabled)
                    }
                }
                .onDelete { offsets in
                    let sorted = (groups[g] ?? []).sorted { $0.sortOrder < $1.sortOrder }
                    for i in offsets { context.delete(sorted[i]) }
                }
            }
        }

        Section {
            let docs = vehicle.documents.sorted { $0.createdAt > $1.createdAt }
            if docs.isEmpty {
                EmptyHint(text: "Keep the owner's manual, insurance, registration papers…")
            }
            ForEach(docs) { doc in
                Button {
                    previewURL = AttachmentIO.tempURL(filename: doc.filename, data: doc.data)
                } label: {
                    AttachmentRow(name: doc.displayName, typeIdentifier: doc.typeIdentifier, size: doc.data.count, date: doc.createdAt)
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(docs[i]) }
            }
            Button { showDocImporter = true } label: { Label("Add document", systemImage: "paperclip") }
        } header: {
            Text("Documents")
        }

        let readings = vehicle.readings.sorted { $0.date > $1.date }
        Section("Mileage log") {
            ForEach(readings) { r in
                LabeledContent {
                    Text(Fmt.km(r.km)).monospacedDigit()
                } label: {
                    VStack(alignment: .leading) {
                        Text(Fmt.date(r.date))
                        if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(readings[i]) }
            }
            Button { sheet = .mileage } label: { Label("Update mileage", systemImage: "gauge.with.dots.needle.67percent") }
        }

        if !vehicle.scheduleSource.isEmpty {
            Section("Schedule source") {
                Text(vehicle.scheduleSource).font(.callout)
                ForEach(vehicle.scheduleSourceURLs, id: \.self) { s in
                    if let url = URL(string: s) {
                        Link(destination: url) {
                            Text(url.host() ?? s).font(.callout).lineLimit(1)
                        }
                    }
                }
            }
        }

        let hidden = vehicle.tasks.filter { !$0.isEnabled }
        if !hidden.isEmpty {
            Section("Hidden items") {
                ForEach(hidden) { t in
                    NavigationLink(value: t) { Text(t.title).foregroundStyle(.secondary) }
                }
            }
        }

        Section {
            Button("Delete vehicle", role: .destructive) { confirmDelete = true }
        }
    }
}

struct RecordRow: View {
    let record: ServiceRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle).font(.subheadline.weight(.medium))
                Text([Fmt.date(record.date), record.odometerKm.map { Fmt.km($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if record.tasks.count > 1 {
                    Text("\(record.tasks.count) items").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let c = record.cost { Text(Fmt.money(c, code: record.currencyCode)).font(.subheadline) }
                if !record.attachments.isEmpty {
                    Label("\(record.attachments.count)", systemImage: "paperclip")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
