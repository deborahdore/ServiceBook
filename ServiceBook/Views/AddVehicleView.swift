import SwiftUI
import SwiftData

enum ScheduleChoice: Hashable {
    case builtIn(String)
    case online
    case pdf
    case empty
}

struct AddVehicleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Called after saving; the mode is set when the user asked for an AI import.
    var onCreated: (Vehicle, ImportMode?) -> Void

    @State private var kind: VehicleKind = .car
    @State private var make = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var variant = ""
    @State private var fuel: FuelType = .petrol
    @State private var nickname = ""
    @State private var plate = ""
    @State private var vin = ""
    @State private var hasRegistration = false
    @State private var registration = Date()
    @State private var kmText = ""
    @State private var historyUnknown = false
    @State private var choice: ScheduleChoice?
    @State private var photo: Data?
    @State private var saving = false
    @State private var downloadError: String?

    private var year: Int { yearText.intValue ?? 0 }
    private var matches: [CatalogEntry] {
        Array(ScheduleLibrary.shared.matches(make: make, model: model, year: year, fuel: fuel, kind: kind).prefix(6))
    }
    private var hasKey: Bool { !(AppSettings.apiKey ?? "").isEmpty }

    private var effectiveChoice: ScheduleChoice {
        if let choice {
            if case .builtIn(let id) = choice, !matches.contains(where: { $0.id == id }) {} else { return choice }
        }
        if let first = matches.first { return .builtIn(first.id) }
        return hasKey ? .online : .empty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    VehiclePhotoField(photo: $photo, kind: kind)
                    Picker("Type", selection: $kind) {
                        ForEach(VehicleKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Make (e.g. Kawasaki)", text: $make)
                        .textInputAutocapitalization(.words)
                    TextField("Model (e.g. Z400)", text: $model)
                        .textInputAutocapitalization(.words)
                    TextField("Model year", text: $yearText)
                        .keyboardType(.numberPad)
                    TextField("Engine / version (e.g. 1.5 TDCi 85 hp)", text: $variant)
                    Picker("Fuel", selection: $fuel) {
                        ForEach(FuelType.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    NumberField(title: "Current mileage", text: $kmText, suffix: "km")
                    Toggle("History unknown", isOn: $historyUnknown)
                } header: {
                    Text("Odometer")
                } footer: {
                    Text(historyUnknown
                         ? "Items you have never logged will be counted from today's mileage, instead of showing as overdue."
                         : "Items you have never logged are counted from new (0 km / first registration). Turn on “History unknown” for a used vehicle without service records.")
                }

                Section("Identification (optional)") {
                    TextField("Nickname", text: $nickname)
                    TextField("Registration plate", text: $plate)
                        .textInputAutocapitalization(.characters)
                    TextField("VIN / frame number", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Toggle("First registration date", isOn: $hasRegistration)
                    if hasRegistration {
                        DatePicker("Registered", selection: $registration, displayedComponents: .date)
                    }
                }

                Section {
                    Picker("Schedule", selection: Binding(get: { effectiveChoice }, set: { choice = $0 })) {
                        ForEach(matches) { t in
                            Text("Library: \(LS(t.model)) \(LS(t.generation ?? ""))").tag(ScheduleChoice.builtIn(t.id))
                        }
                        Text("Find the manual online (AI)").tag(ScheduleChoice.online)
                        Text("Upload manual or booklet (AI)").tag(ScheduleChoice.pdf)
                        Text("Start empty").tag(ScheduleChoice.empty)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Maintenance schedule")
                } footer: {
                    switch effectiveChoice {
                    case .builtIn(let id):
                        if ScheduleLibrary.shared.entry(id)?.generic == true {
                            Text("A brand-wide plan from the manufacturer's service documents. Check the items that depend on your engine, and edit any item afterwards.")
                        } else {
                            Text("A researched schedule from the manufacturer's documents. You can edit every item afterwards.")
                        }
                    case .online:
                        Text(hasKey
                             ? "Claude will read the owner's manual and build the checklist. You review it before anything is added."
                             : "Needs a Claude API key — add it in Settings. You can also do this later from the vehicle screen.")
                    case .pdf:
                        Text(hasKey || OnDeviceAI.isAvailable || LocalModel.ready != nil
                             ? "Upload the manual or service booklet (PDF, photos or scan). Claude or a model on this iPhone builds the checklist, and you review it before anything is added."
                             : "Needs a Claude API key, Apple Intelligence, or the free on-device model (Settings → On-device model). You can also do this later from the vehicle screen.")
                    case .empty:
                        Text("Add items yourself, or import a schedule later from the vehicle screen.")
                    }
                }
            }
            .navigationTitle("New vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(make.trimmingCharacters(in: .whitespaces).isEmpty && model.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .disabled(saving)
            .task { await ScheduleLibrary.shared.refresh() }
            .alert("Schedule not downloaded", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
                Button("Try again") { save() }
                Button("Save without schedule") { choice = .empty; finish(nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(downloadError ?? "")
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .motorcycle || newKind == .scooter { fuel = .petrol }
            }
        }
    }

    /// Downloads the chosen catalog schedule first, then creates the vehicle.
    private func save() {
        guard case .builtIn(let id) = effectiveChoice, let entry = ScheduleLibrary.shared.entry(id) else {
            finish(nil)
            return
        }
        saving = true
        Task {
            do {
                finish(try await ScheduleLibrary.shared.template(for: entry))
            } catch {
                saving = false
                downloadError = error.localizedDescription
            }
        }
    }

    private func finish(_ template: ScheduleTemplate?) {
        let vehicle = Vehicle(name: nickname.trimmingCharacters(in: .whitespaces),
                              make: make.trimmingCharacters(in: .whitespaces),
                              modelName: model.trimmingCharacters(in: .whitespaces),
                              year: year, kind: kind, fuel: fuel)
        vehicle.variant = variant
        vehicle.plate = plate
        vehicle.vin = vin
        vehicle.firstRegistration = hasRegistration ? registration : nil
        vehicle.photo = photo
        context.insert(vehicle)

        let km = kmText.intValue ?? 0
        let reading = OdometerReading(km: km, note: L("Starting mileage"))
        context.insert(reading)
        reading.vehicle = vehicle

        if historyUnknown {
            vehicle.baselineKm = km
            vehicle.baselineDate = Date()
        }

        var mode: ImportMode?
        switch effectiveChoice {
        case .builtIn:
            if let template { ScheduleApplier.apply(template, to: vehicle, in: context, replace: false) }
        case .online: mode = .online
        case .pdf: mode = .pdf
        case .empty: break
        }
        try? context.save()
        ReminderScheduler.reschedule(context: context)
        onCreated(vehicle, mode)
        dismiss()
    }
}

struct EditVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vehicle: Vehicle
    @State private var yearText = ""
    @State private var hasRegistration = false
    @State private var registration = Date()
    @State private var historyUnknown = false
    @State private var baselineKmText = ""
    @State private var baselineDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    VehiclePhotoField(photo: $vehicle.photo, kind: vehicle.kind)
                    Picker("Type", selection: Binding(get: { vehicle.kind }, set: { vehicle.kind = $0 })) {
                        ForEach(VehicleKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Nickname", text: $vehicle.name)
                    TextField("Make", text: $vehicle.make)
                    TextField("Model", text: $vehicle.modelName)
                    TextField("Model year", text: $yearText).keyboardType(.numberPad)
                    TextField("Engine / version", text: $vehicle.variant)
                    Picker("Fuel", selection: Binding(get: { vehicle.fuel }, set: { vehicle.fuel = $0 })) {
                        ForEach(FuelType.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Identification") {
                    TextField("Registration plate", text: $vehicle.plate)
                    TextField("VIN / frame number", text: $vehicle.vin)
                    Toggle("First registration date", isOn: $hasRegistration)
                    if hasRegistration {
                        DatePicker("Registered", selection: $registration, displayedComponents: .date)
                    }
                }
                Section {
                    Toggle("History unknown", isOn: $historyUnknown)
                    if historyUnknown {
                        NumberField(title: "Tracking from", text: $baselineKmText, suffix: "km")
                        DatePicker("Since", selection: $baselineDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Items never logged are counted from this mileage and date instead of from new.")
                }
                Section("Notes") {
                    TextField("Notes", text: $vehicle.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle("Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        vehicle.year = yearText.intValue ?? 0
                        vehicle.firstRegistration = hasRegistration ? registration : nil
                        if historyUnknown {
                            vehicle.baselineKm = baselineKmText.intValue ?? 0
                            vehicle.baselineDate = baselineDate
                        } else {
                            vehicle.baselineKm = nil
                            vehicle.baselineDate = nil
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                yearText = vehicle.year > 0 ? String(vehicle.year) : ""
                hasRegistration = vehicle.firstRegistration != nil
                registration = vehicle.firstRegistration ?? Date()
                historyUnknown = vehicle.baselineKm != nil || vehicle.baselineDate != nil
                baselineKmText = vehicle.baselineKm.map(String.init) ?? String(vehicle.currentKm)
                baselineDate = vehicle.baselineDate ?? Date()
            }
        }
    }
}
