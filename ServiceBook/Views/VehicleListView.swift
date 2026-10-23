import SwiftUI
import SwiftData

enum ImportMode: String {
    case online, pdf
}

struct ImportRequest: Identifiable {
    let id = UUID()
    let vehicle: Vehicle
    let mode: ImportMode
}

struct VehicleListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    @State private var showAdd = false
    @State private var showSettings = false
    @State private var pendingImport: ImportRequest?
    @State private var importRequest: ImportRequest?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if vehicles.isEmpty {
                    ContentUnavailableView {
                        Label("No vehicles yet", systemImage: "car.2.fill")
                    } description: {
                        Text("Add your car or motorcycle to get its maintenance schedule, log services and keep receipts.")
                    } actions: {
                        Button("Add a vehicle") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(vehicles) { vehicle in
                            NavigationLink(value: vehicle) {
                                VehicleRow(vehicle: vehicle)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("My vehicles")
            .navigationDestination(for: Vehicle.self) { VehicleDetailView(vehicle: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add vehicle")
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: {
                if let p = pendingImport {
                    pendingImport = nil
                    path.append(p.vehicle)
                    importRequest = p
                }
            }) {
                AddVehicleView { vehicle, mode in
                    if let mode { pendingImport = ImportRequest(vehicle: vehicle, mode: mode) }
                }
            }
            .sheet(item: $importRequest) { req in
                ManualImportView(vehicle: req.vehicle, mode: req.mode)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .onAppear { ReminderScheduler.reschedule(context: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ReminderScheduler.reschedule(context: context) }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(vehicles[i]) }
        try? context.save()
        ReminderScheduler.reschedule(context: context)
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        let counts = vehicle.statusCounts()
        HStack(spacing: 14) {
            Image(systemName: vehicle.kind.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.displayName).font(.headline)
                Text(Fmt.km(vehicle.currentKm)).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if counts.overdue > 0 {
                        Label("\(counts.overdue) overdue", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    if counts.soon > 0 {
                        Label("\(counts.soon) due soon", systemImage: "clock.fill")
                            .foregroundStyle(.orange)
                    }
                    if counts.overdue == 0 && counts.soon == 0 && !vehicle.tasks.isEmpty {
                        Label("All up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }
}
