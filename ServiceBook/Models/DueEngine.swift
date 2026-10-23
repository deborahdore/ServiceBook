import Foundation

enum DueStatus: Int, Comparable, CaseIterable {
    case overdue = 0
    case dueSoon = 1
    case upcoming = 2
    case noInterval = 3
    case completed = 4   // one-time item already done

    static func < (lhs: DueStatus, rhs: DueStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .overdue: "Overdue"
        case .dueSoon: "Due soon"
        case .upcoming: "Upcoming"
        case .noInterval: "As needed"
        case .completed: "Done"
        }
    }
}

/// Snapshot of the vehicle values the due computation needs.
struct DueState {
    var currentKm: Int
    var startDate: Date
    var baselineKm: Int?
    var baselineDate: Date?
}

struct DueInfo {
    var status: DueStatus
    var dueKm: Int?
    var dueDate: Date?
    var remainingKm: Int?
    var remainingDays: Int?
    /// 0 = just done, 1 = due now (above 1 when overdue).
    var progress: Double
    var lastDoneDate: Date?
    var lastDoneKm: Int?

    var dueText: String {
        var parts: [String] = []
        if let k = dueKm {
            if let r = remainingKm {
                parts.append(r >= 0 ? "at \(Fmt.km(k)) · in \(Fmt.km(r))" : "at \(Fmt.km(k)) · \(Fmt.km(-r)) ago")
            } else {
                parts.append("at \(Fmt.km(k))")
            }
        }
        if let d = dueDate {
            var text = "on \(Fmt.date(d))"
            if let days = remainingDays { text += " · " + Self.relative(days) }
            parts.append(text)
        }
        return parts.joined(separator: "\nor ")
    }

    static func relative(_ days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1...60: return "in \(days) days"
        case 61...: return "in \(days / 30) months"
        case -60 ... -1: return "\(-days) days ago"
        default: return "\(-days / 30) months ago"
        }
    }
}

extension MaintenanceTask {
    func dueInfo(_ state: DueState, now: Date = Date()) -> DueInfo {
        let cal = Calendar.current
        let last = lastRecord
        let lastKm = last?.odometerKm
        let lastDate = last?.date
        let hasBaseline = state.baselineKm != nil || state.baselineDate != nil

        if oneTime {
            // Done once logged — or skipped when tracking started after it was due.
            let coveredByBaseline = hasBaseline && (firstKm ?? 0) <= (state.baselineKm ?? 0)
            if last != nil || coveredByBaseline {
                return DueInfo(status: .completed, progress: 0, lastDoneDate: lastDate, lastDoneKm: lastKm)
            }
        }

        var dueKm: Int?
        var dueDate: Date?
        var spanKm: Int?
        var spanMonths: Int?

        if let last, !oneTime {
            if let interval = intervalKm, let lk = last.odometerKm { dueKm = lk + interval; spanKm = interval }
            if let m = intervalMonths { dueDate = cal.date(byAdding: .month, value: m, to: last.date); spanMonths = m }
        } else if hasBaseline && !oneTime {
            if let interval = intervalKm, let b = state.baselineKm { dueKm = b + interval; spanKm = interval }
            if let m = intervalMonths, let b = state.baselineDate { dueDate = cal.date(byAdding: .month, value: m, to: b); spanMonths = m }
        } else {
            if let k = firstKm ?? intervalKm { dueKm = k; spanKm = k }
            if let m = firstMonths ?? intervalMonths {
                dueDate = cal.date(byAdding: .month, value: m, to: state.startDate); spanMonths = m
            }
        }

        if dueKm == nil && dueDate == nil {
            return DueInfo(status: .noInterval, progress: 0, lastDoneDate: lastDate, lastDoneKm: lastKm)
        }

        let remainingKm = dueKm.map { $0 - state.currentKm }
        let remainingDays = dueDate.map {
            cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: $0)).day ?? 0
        }

        var progress = 0.0
        if let r = remainingKm, let span = spanKm, span > 0 {
            progress = max(progress, 1 - Double(r) / Double(span))
        }
        if let d = remainingDays, let m = spanMonths, m > 0 {
            progress = max(progress, 1 - Double(d) / (Double(m) * 30.44))
        }

        // "Due soon" = within 10 % of the interval (km: 100…1,000 km, time: 5…30 days).
        let soonKm = min(1_000, max(100, (spanKm ?? 10_000) / 10))
        let soonDays = min(30, max(5, (spanMonths ?? 12) * 3))

        let status: DueStatus
        if (remainingKm ?? 1) <= 0 || (remainingDays ?? 1) <= 0 {
            status = .overdue
        } else if (remainingKm ?? Int.max) <= soonKm || (remainingDays ?? Int.max) <= soonDays {
            status = .dueSoon
        } else {
            status = .upcoming
        }

        return DueInfo(status: status, dueKm: dueKm, dueDate: dueDate,
                       remainingKm: remainingKm, remainingDays: remainingDays,
                       progress: progress, lastDoneDate: lastDate, lastDoneKm: lastKm)
    }
}

struct ScheduleRow: Identifiable {
    let task: MaintenanceTask
    let info: DueInfo
    var id: UUID { task.id }
}

extension Vehicle {
    /// Enabled items with their due info, most urgent first.
    func scheduleRows(now: Date = Date()) -> [ScheduleRow] {
        let state = dueState
        return tasks.filter(\.isEnabled)
            .map { ScheduleRow(task: $0, info: $0.dueInfo(state, now: now)) }
            .sorted { a, b in
                if a.info.status != b.info.status { return a.info.status < b.info.status }
                if a.info.progress != b.info.progress { return a.info.progress > b.info.progress }
                return a.task.sortOrder < b.task.sortOrder
            }
    }
}
