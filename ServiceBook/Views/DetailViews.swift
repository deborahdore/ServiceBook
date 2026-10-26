import SwiftUI
import SwiftData
import QuickLook

// MARK: - Service record

struct RecordDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: ServiceRecord
    @State private var editing = false
    @State private var previewURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: record.kind.label)
                LabeledContent("Date", value: Fmt.date(record.date))
                if let km = record.odometerKm { LabeledContent("Odometer", value: Fmt.km(km)) }
                if let c = record.cost { LabeledContent("Cost", value: Fmt.money(c, code: record.currencyCode)) }
                if !record.shop.isEmpty { LabeledContent("Workshop", value: record.shop) }
            }

            if !record.partPosition.isEmpty || !record.partBrand.isEmpty || !record.partSize.isEmpty || !record.partDetails.isEmpty {
                Section(record.kind == .tyres ? "Tyres" : "Part") {
                    if !record.partPosition.isEmpty { LabeledContent(record.kind == .tyres ? "Position" : "Part", value: L(record.partPosition)) }
                    if !record.partBrand.isEmpty { LabeledContent("Brand & model", value: record.partBrand) }
                    if !record.partSize.isEmpty { LabeledContent(record.kind == .tyres ? "Size" : "Part number", value: record.partSize) }
                    if !record.partDetails.isEmpty { Text(record.partDetails).font(.callout) }
                }
            }

            if !record.tasks.isEmpty {
                Section("Items done (\(record.tasks.count))") {
                    ForEach(record.tasks.sorted { $0.sortOrder < $1.sortOrder }) { t in
                        Label(LS(t.title), systemImage: "checkmark.circle.fill")
                    }
                }
            }

            if !record.notes.isEmpty {
                Section("Notes") { Text(record.notes) }
            }

            Section("Receipts & documents") {
                if record.attachments.isEmpty { EmptyHint(text: "No files attached. Tap Edit to add receipts.") }
                ForEach(record.attachments.sorted { $0.createdAt < $1.createdAt }) { a in
                    Button {
                        previewURL = AttachmentIO.tempURL(filename: a.filename, data: a.data)
                    } label: {
                        AttachmentRow(name: a.displayName, typeIdentifier: a.typeIdentifier, size: a.data.count, date: a.createdAt)
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Button("Delete entry", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(record.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) {
            if let v = record.vehicle { LogServiceView(vehicle: v, record: record) }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Delete this entry and its attachments?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(record)
                try? context.save()
                dismiss()
            }
        }
    }
}

// MARK: - Maintenance item

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: MaintenanceTask
    @State private var editing = false
    @State private var logging = false
    @State private var confirmDelete = false

    var body: some View {
        let info = task.vehicle.map { task.dueInfo($0.dueState) }
        List {
            if let info {
                Section {
                    HStack {
                        Image(systemName: info.status.symbol).foregroundStyle(info.status.color).font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            StatusPill(status: info.status)
                            if !info.dueText.isEmpty, info.status != .completed {
                                Text(L("Due %@", info.dueText)).font(.subheadline)
                            }
                        }
                    }
                    if info.status != .completed && info.status != .noInterval {
                        ProgressView(value: min(max(info.progress, 0), 1)).tint(info.status.color)
                    }
                    if let d = info.lastDoneDate {
                        LabeledContent("Last done", value: Fmt.date(d) + (info.lastDoneKm.map { " · \(Fmt.km($0))" } ?? ""))
                    }
                    Button {
                        logging = true
                    } label: {
                        Label("Mark as done", systemImage: "checkmark.circle")
                    }
                }
            }

            Section("Schedule") {
                LabeledContent("Action", value: task.action.label)
                LabeledContent("Interval", value: task.intervalText)
                if !task.oneTime, task.firstKm != nil || task.firstMonths != nil {
                    LabeledContent("First time", value: [task.firstKm.map { Fmt.km($0) }, task.firstMonths.map { Fmt.months($0) }]
                        .compactMap { $0 }.joined(separator: " \(L("or")) "))
                }
                Toggle("Show in schedule", isOn: $task.isEnabled)
            }

            if !task.spec.isEmpty {
                Section("Specification") { Text(LS(task.spec)).textSelection(.enabled) }
            }
            if !task.notes.isEmpty {
                Section("Notes") { Text(LS(task.notes)).textSelection(.enabled) }
            }
            if !task.sourceRef.isEmpty {
                Section("Source") { Text(LS(task.sourceRef)).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("History") {
                let history = task.records.sorted { $0.date > $1.date }
                if history.isEmpty { EmptyHint(text: "Not logged yet.") }
                ForEach(history) { r in
                    NavigationLink(value: r) { RecordRow(record: r) }
                }
            }

            Section {
                Button("Delete item", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(LS(task.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) {
            if let v = task.vehicle { TaskEditView(vehicle: v, task: task) }
        }
        .sheet(isPresented: $logging) {
            if let v = task.vehicle { LogServiceView(vehicle: v, preselected: [task]) }
        }
        .confirmationDialog("Delete “\(LS(task.title))”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(task)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Past history entries are kept. To keep the item but hide it, turn off “Show in schedule”.")
        }
    }
}

struct TaskEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    var task: MaintenanceTask?

    @State private var title = ""
    @State private var action: TaskAction = .inspect
    @State private var category = "general"
    @State private var kmText = ""
    @State private var monthsText = ""
    @State private var oneTime = false
    @State private var firstKmText = ""
    @State private var firstMonthsText = ""
    @State private var spec = ""
    @State private var notes = ""
    @State private var loaded = false

    static let categories = ["general", "oil", "filters", "brakes", "tyres", "wheels", "chain", "cooling", "fuel", "ignition",
                             "electrical", "engine", "suspension", "steering", "transmission", "climate", "body", "chassis",
                             "safety", "emissions", "controls", "owner", "legal", "service"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (e.g. Chain kit)", text: $title)
                    Picker("Action", selection: $action) {
                        ForEach(TaskAction.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(Self.categories, id: \.self) { c in
                            Label(L(c.capitalized), systemImage: TaskCategory.symbol(for: c)).tag(c)
                        }
                    }
                }
                Section {
                    Toggle("Only once", isOn: $oneTime)
                    if oneTime {
                        NumberField(title: "At", text: $firstKmText, suffix: "km")
                        NumberField(title: "Or after", text: $firstMonthsText, suffix: L("months"))
                    } else {
                        NumberField(title: "Every", text: $kmText, suffix: "km")
                        NumberField(title: "Or every", text: $monthsText, suffix: L("months"))
                        NumberField(title: "First at", text: $firstKmText, suffix: "km")
                        NumberField(title: "Or first after", text: $firstMonthsText, suffix: L("months"))
                    }
                } header: {
                    Text("Interval — whichever comes first")
                } footer: {
                    Text(oneTime ? "For a one-off job such as the run-in service."
                                 : "Leave “first” empty if the first time is the same as the interval.")
                }
                Section("Details") {
                    TextField("Specification (oil grade, part number, torque…)", text: $spec, axis: .vertical).lineLimit(1...5)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...10)
                }
            }
            .navigationTitle(task == nil ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard let t = task else { return }
                title = LS(t.title)
                action = t.action
                category = Self.categories.contains(t.category) ? t.category : "general"
                kmText = t.intervalKm.map(String.init) ?? ""
                monthsText = t.intervalMonths.map(String.init) ?? ""
                oneTime = t.oneTime
                firstKmText = t.firstKm.map(String.init) ?? ""
                firstMonthsText = t.firstMonths.map(String.init) ?? ""
                spec = LS(t.spec)
                notes = LS(t.notes)
            }
        }
    }

    private func save() {
        let t: MaintenanceTask
        if let task {
            t = task
        } else {
            t = MaintenanceTask(title: title)
            t.isCustom = true
            t.sortOrder = (vehicle.tasks.map(\.sortOrder).max() ?? 0) + 1
            context.insert(t)
            t.vehicle = vehicle
        }
        // Unchanged built-in text keeps its English key, so it still follows the app language.
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        if newTitle != LS(t.title) { t.title = newTitle }
        t.action = action
        t.category = category
        t.oneTime = oneTime
        t.intervalKm = oneTime ? nil : kmText.intValue
        t.intervalMonths = oneTime ? nil : monthsText.intValue
        t.firstKm = firstKmText.intValue
        t.firstMonths = firstMonthsText.intValue
        if spec != LS(t.spec) { t.spec = spec }
        if notes != LS(t.notes) { t.notes = notes }
        try? context.save()
        dismiss()
    }
}

// MARK: - Mileage

struct MileageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var kmText = ""
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: "Odometer", text: $kmText, suffix: "km")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if let km = kmText.intValue, km < vehicle.currentKm {
                        Text("This is lower than the last known mileage (\(Fmt.km(vehicle.currentKm))).").foregroundStyle(.orange)
                    } else {
                        Text("Last known: \(Fmt.km(vehicle.currentKm)). Mileage-based items update immediately.")
                    }
                }
            }
            .navigationTitle("Update mileage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let km = kmText.intValue else { return }
                        let r = OdometerReading(date: date, km: km, note: note)
                        context.insert(r)
                        r.vehicle = vehicle
                        try? context.save()
                        dismiss()
                    }
                    .disabled(kmText.intValue == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Built-in schedules

struct BuiltInSchedulePicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var chosen: ScheduleTemplate?
    @State private var replace = true

    var body: some View {
        NavigationStack {
            let lib = ScheduleLibrary.shared
            let matching = lib.matches(make: vehicle.make, model: vehicle.modelName, year: vehicle.year, fuel: vehicle.fuel)
            let others = lib.templates.filter { t in !matching.contains { $0.id == t.id } }
            List {
                if !matching.isEmpty {
                    Section("Matching your vehicle") {
                        ForEach(matching) { t in row(t) }
                    }
                }
                Section(matching.isEmpty ? "Available schedules" : "Other schedules") {
                    ForEach(others) { t in row(t) }
                }
                Section {
                    Text("Your vehicle isn't listed? Use “Find the manual online (AI)” or “Import a manual PDF (AI)”. Contributions of new schedules are welcome on GitHub.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Built-in schedules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .confirmationDialog("Load \(chosen?.title ?? "")", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
                if let t = chosen {
                    if !vehicle.tasks.isEmpty {
                        Button("Replace current schedule") { load(t, replace: true) }
                        Button("Add missing items only") { load(t, replace: false) }
                    } else {
                        Button("Load \(t.tasks.count) items") { load(t, replace: false) }
                    }
                }
            } message: {
                Text("Items you created yourself, and items with history, are always kept.")
            }
        }
    }

    private func row(_ t: ScheduleTemplate) -> some View {
        Button { chosen = t } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(t.make) \(t.model)").font(.headline).foregroundStyle(.primary)
                if let g = t.generation { Text(LS(g)).font(.caption).foregroundStyle(.secondary) }
                Text(L("%lld items", t.tasks.count) + " · " + L("%lld specs", t.specs?.count ?? 0)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func load(_ t: ScheduleTemplate, replace: Bool) {
        ScheduleApplier.apply(t, to: vehicle, in: context, replace: replace)
        try? context.save()
        dismiss()
    }
}
