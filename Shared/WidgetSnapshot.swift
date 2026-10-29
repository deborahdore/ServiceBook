import Foundation

/// What the home-screen widget shows. The app writes it to the shared App Group (on launch and when it goes
/// to the background); the widget reads it and works out from the due dates what has become due since.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.io.github.deborahdore.ServiceBook"
    static let key = "widgetSnapshot"

    var language: String = "en"
    var locale: String = "en"
    var vehicles: [VehicleSummary] = []

    struct VehicleSummary: Codable, Identifiable {
        var id: UUID
        var name: String
        var symbol: String
        var km: Int
        /// Enabled items with a due point, most urgent first.
        var items: [DueItem]
    }

    struct DueItem: Codable, Identifiable {
        var id: UUID
        var title: String
        var symbol: String
        var dueDate: Date?
        var remainingKm: Int?
        /// Thresholds for "due soon", as computed by the app's DueEngine.
        var soonKm: Int
        var soonDays: Int
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }
}
