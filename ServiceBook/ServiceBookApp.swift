import SwiftUI
import SwiftData

@main
struct ServiceBookApp: App {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.system.rawValue

    init() {
        AppLanguage.syncWithSystemSettings()
    }

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .environment(\.locale, AppLanguage.locale)
                .id(language)   // rebuild every screen when the language changes
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
