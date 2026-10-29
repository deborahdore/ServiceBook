import Foundation
import SwiftData
import WidgetKit

/// Copies what the widget needs into the shared App Group and asks WidgetKit to redraw.
enum WidgetSync {
    @MainActor
    static func update(context: ModelContext) {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let summaries = vehicles.map { v -> WidgetSnapshot.VehicleSummary in
            let items = v.scheduleRows()
                .filter { $0.info.status <= .upcoming }
                .map { row in
                    WidgetSnapshot.DueItem(id: row.task.id, title: LS(row.task.title),
                                           symbol: TaskCategory.symbol(for: row.task.category),
                                           dueDate: row.info.dueDate, remainingKm: row.info.remainingKm,
                                           soonKm: row.info.soonKm, soonDays: row.info.soonDays)
                }
            return WidgetSnapshot.VehicleSummary(id: v.id, name: v.displayName, symbol: v.kind.symbol,
                                                 km: v.currentKm, items: items)
        }
        WidgetSnapshot(language: AppLanguage.code, locale: AppLanguage.locale.identifier, vehicles: summaries).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
