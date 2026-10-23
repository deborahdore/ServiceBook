import Foundation
import SwiftData
import UserNotifications

/// Schedules local reminders for date-based due items (km-based items are shown in the app).
enum ReminderScheduler {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    @MainActor
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard UserDefaults.standard.bool(forKey: AppSettings.notificationsKey) else { return }
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []

        let now = Date()
        var items: [(date: Date, title: String, body: String, id: String)] = []
        for v in vehicles {
            let state = v.dueState
            for t in v.tasks where t.isEnabled {
                let info = t.dueInfo(state, now: now)
                guard let due = info.dueDate, info.status != .completed else { continue }
                // Remind one week before and on the due day, at 9:00.
                for (offset, label) in [(-7, "due in one week"), (0, "due today")] {
                    guard let day = Calendar.current.date(byAdding: .day, value: offset, to: due),
                          let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                          fire > now else { continue }
                    items.append((fire, v.displayName, "\(t.title) — \(label)", "\(t.id.uuidString)-\(offset)"))
                }
            }
        }
        // iOS keeps at most 64 pending requests.
        for item in items.sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
