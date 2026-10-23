import SwiftUI
import SwiftData

@main
struct ServiceBookApp: App {
    var body: some Scene {
        WindowGroup {
            VehicleListView()
        }
        .modelContainer(for: [
            Vehicle.self,
            MaintenanceTask.self,
            ServiceRecord.self,
            OdometerReading.self,
            SpecNote.self,
            Attachment.self,
        ])
    }
}
