import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Create or edit a service / tyre change / repair entry, with the receipts attached.
struct LogServiceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    var record: ServiceRecord?
    var preselected: [MaintenanceTask] = []
    var initialKind: RecordKind = .service

    @State private var kind: RecordKind = .service
    @State private var title = ""
    @State private var date = Date()
    @State private var kmText = ""
    @State private var selected: Set<UUID> = []
    @State private var costText = ""
    @State private var currency = "EUR"
    @State private var shop = ""
    @State private var notes = ""
    @State private var position = ""
    @State private var brand = ""
    @State private var size = ""
    @State private var details = ""
    @State private var pending: [PendingAttachment] = []
    @State private var removed: Set<UUID> = []
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loaded = false

    private static let tyrePositions = ["Front", "Rear", "Front & rear", "Front left", "Front right", "Rear left", "Rear right", "All four", "Spare"]
    private static let currencies = ["EUR", "USD", "GBP", "CHF", "CAD", "AUD", "JPY", "SEK", "NOK", "DKK", "PLN"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(RecordKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField(titlePlaceholder, text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    NumberField(title: "Odometer", text: $kmText, suffix: "km")
                    if let km = kmText.intValue, km < vehicle.currentKm, record == nil, Calendar.current.isDateInToday(date) {
                        Text("Lower than the current mileage (\(Fmt.km(vehicle.currentKm))). Fine for an older entry — set its date.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                if kind == .tyres || kind == .part {
                    Section(kind == .tyres ? "Tyres" : "Part") {
                        if kind == .tyres {
                            Picker("Position", selection: $position) {
                                Text("—").tag("")
                                ForEach(Self.tyrePositions, id: \.self) { Text(L($0)).tag($0) }
                            }
                        } else {
                            TextField("Part (e.g. battery, chain kit)", text: $position)
                        }
                        TextField("Brand & model", text: $brand)
                        TextField(kind == .tyres ? "Size (e.g. 110/70 R17)" : "Part number", text: $size)
                        TextField(kind == .tyres ? "DOT code / pressures / notes" : "Details", text: $details)
                    }
                }

                Section {
                    NavigationLink {
                        TaskPickerView(vehicle: vehicle, selection: $selected)
                    } label: {
                        LabeledContent("Items done", value: selected.isEmpty ? L("None") : "\(selected.count)")
                    }
                    ForEach(vehicle.tasks.filter { selected.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }) { t in
                        Label(LS(t.title), systemImage: "checkmark").font(.callout)
                    }
                } header: {
                    Text("Schedule items")
                } footer: {
                    Text("The next due date and mileage of each selected item restart from this entry.")
                }

                Section("Cost & workshop") {
                    HStack {
                        TextField("Cost", text: $costText).keyboardType(.decimalPad)
                        Picker("", selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    TextField("Workshop / dealer (or DIY)", text: $shop)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...8)
                }

                Section("Receipts & documents") {
                    if let record {
                        ForEach(record.attachments.filter { !removed.contains($0.id) }) { a in
                            AttachmentRow(name: a.displayName, typeIdentifier: a.typeIdentifier, size: a.data.count, date: a.createdAt)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { removed.insert(a.id) }
                                }
                        }
                    }
                    ForEach(pending) { p in
                        AttachmentRow(name: p.filename, typeIdentifier: p.typeIdentifier, size: p.data.count)
                            .swipeActions {
                                Button("Remove", role: .destructive) { pending.removeAll { $0.id == p.id } }
                            }
                    }
                    Button { showImporter = true } label: { Label("Add PDF or file", systemImage: "doc.badge.plus") }
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Add photo", systemImage: "photo.badge.plus")
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button { showScanner = true } label: { Label("Scan receipt", systemImage: "doc.viewfinder") }
                    }
                }
            }
            .navigationTitle(record == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                pending += urls.compactMap(AttachmentIO.read)
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { data in
                    if let data {
                        pending.append(PendingAttachment(filename: L("Receipt %@.pdf", Fmt.date(Date())),
                                                         typeIdentifier: UTType.pdf.identifier, data: data))
                    }
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
                            pending.append(PendingAttachment(filename: L("Photo %lld.jpg", pending.count + 1),
                                                             typeIdentifier: UTType.jpeg.identifier, data: jpeg))
                        }
                    }
                    photoItems = []
                }
            }
            .onAppear(perform: load)
        }
    }

    private var titlePlaceholder: String {
        switch kind {
        case .service: L("Title (e.g. Annual service)")
        case .tyres: L("Title (e.g. New rear tyre)")
        case .part: L("Title (e.g. New battery)")
        case .repair: L("Title (e.g. Clutch cable replaced)")
        case .inspection: L("Title (e.g. Contrôle technique)")
        case .other: L("Title")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        currency = Locale.current.currency?.identifier ?? "EUR"
        if !Self.currencies.contains(currency) { currency = "EUR" }
        if let r = record {
            kind = r.kind
            title = r.title
            date = r.date
            kmText = r.odometerKm.map(String.init) ?? ""
            selected = Set(r.tasks.map(\.id))
            costText = r.cost.map { String(format: "%.2f", $0) } ?? ""
            currency = r.currencyCode
            shop = r.shop
            notes = r.notes
            position = r.partPosition
            brand = r.partBrand
            size = r.partSize
            details = r.partDetails
        } else {
            kind = initialKind
            kmText = vehicle.currentKm > 0 ? String(vehicle.currentKm) : ""
            selected = Set(preselected.map(\.id))
            if let last = vehicle.records.max(by: { $0.date < $1.date }) {
                currency = last.currencyCode
                if kind == .service { shop = last.shop }
            }
        }
    }

    private func save() {
        let r: ServiceRecord
        if let record {
            r = record
        } else {
            r = ServiceRecord()
            context.insert(r)
            r.vehicle = vehicle
        }
        r.kind = kind
        r.title = title.trimmingCharacters(in: .whitespaces)
        r.date = date
        r.odometerKm = kmText.intValue
        r.cost = costText.doubleValue
        r.currencyCode = currency
        r.shop = shop
        r.notes = notes
        let isPart = kind == .tyres || kind == .part
        r.partPosition = isPart ? position : ""
        r.partBrand = isPart ? brand : ""
        r.partSize = isPart ? size : ""
        r.partDetails = isPart ? details : ""
        r.tasks = vehicle.tasks.filter { selected.contains($0.id) }

        for a in r.attachments where removed.contains(a.id) { context.delete(a) }
        for p in pending {
            let a = Attachment(filename: p.filename, typeIdentifier: p.typeIdentifier, data: p.data)
            context.insert(a)
            a.record = r
        }
        try? context.save()
        dismiss()
    }
}

/// Multi-select list of the vehicle's schedule items, due items first.
struct TaskPickerView: View {
    let vehicle: Vehicle
    @Binding var selection: Set<UUID>
    @State private var search = ""

    var body: some View {
        let rows = vehicle.scheduleRows().filter {
            search.isEmpty || LS($0.task.title).localizedCaseInsensitiveContains(search)
        }
        List {
            ForEach(rows) { row in
                Button {
                    if selection.contains(row.task.id) { selection.remove(row.task.id) } else { selection.insert(row.task.id) }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(row.task.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(row.task.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LS(row.task.title)).foregroundStyle(.primary)
                            Text("\(row.task.action.label) · \(row.task.intervalText)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.info.status == .overdue || row.info.status == .dueSoon {
                            StatusPill(status: row.info.status)
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Items done")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select all due") {
                        for r in vehicle.scheduleRows() where r.info.status == .overdue || r.info.status == .dueSoon {
                            selection.insert(r.task.id)
                        }
                    }
                    Button("Clear selection") { selection.removeAll() }
                } label: {
                    Image(systemName: "checklist")
                }
            }
        }
    }
}
