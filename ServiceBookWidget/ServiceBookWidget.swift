import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration: which vehicle to show

struct SelectVehicleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Vehicle"
    static var description = IntentDescription("Choose which vehicle the widget shows.")

    /// Empty = the vehicle that needs attention the most.
    @Parameter(title: "Vehicle") var vehicle: VehicleEntity?
}

struct VehicleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Vehicle"
    static var defaultQuery = VehicleQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct VehicleQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [VehicleEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [VehicleEntity] {
        (WidgetSnapshot.load()?.vehicles ?? []).map { VehicleEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Text in the language chosen in the app

struct Loc {
    let bundle: Bundle
    let locale: Locale

    init(_ snapshot: WidgetSnapshot?) {
        let supported = ["en", "it", "fr", "es", "pt"]
        let code = snapshot?.language
            ?? Locale.preferredLanguages.map { String($0.prefix(2)) }.first { supported.contains($0) } ?? "en"
        bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
        locale = snapshot.map { Locale(identifier: $0.locale) } ?? .current
    }

    func callAsFunction(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, locale: locale, arguments: args)
    }

    func km(_ value: Int) -> String { value.formatted(.number.locale(locale)) + " km" }
}

// MARK: - Due status at a given day (same rules as DueEngine)

enum ItemStatus: Int { case overdue, soon, ok }

extension WidgetSnapshot.DueItem {
    func days(on date: Date) -> Int? {
        let cal = Calendar.current
        return dueDate.map { cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: $0)).day ?? 0 }
    }

    func status(on date: Date) -> ItemStatus {
        let d = days(on: date)
        if (remainingKm ?? 1) <= 0 || (d ?? 1) <= 0 { return .overdue }
        if (remainingKm ?? .max) <= soonKm || (d ?? .max) <= soonDays { return .soon }
        return .ok
    }

    /// The closer of the two limits: "in 1,200 km" or "in 12 days".
    func dueText(on date: Date, _ loc: Loc) -> String {
        let d = days(on: date)
        if let k = remainingKm, d == nil || (k <= soonKm && (d ?? 0) > soonDays) {
            return k > 0 ? loc("in %@", loc.km(k)) : loc("%@ over", loc.km(-k))
        }
        guard let days = d else { return "" }
        switch days {
        case 0: return loc("today")
        case 1...60: return loc("in %lld days", days)
        case 61...: return loc("in %lld months", days / 30)
        case -60 ... -1: return loc("%lld days ago", -days)
        default: return loc("%lld months ago", -days / 30)
        }
    }
}

struct DueRow: Identifiable {
    let item: WidgetSnapshot.DueItem
    let status: ItemStatus
    var id: UUID { item.id }
}

// MARK: - Timeline

struct DueEntry: TimelineEntry {
    let date: Date
    let vehicle: WidgetSnapshot.VehicleSummary?
    let loc: Loc

    /// Most urgent first, keeping the app's order inside each status.
    var rows: [DueRow] {
        (vehicle?.items ?? []).map { DueRow(item: $0, status: $0.status(on: date)) }
            .enumerated()
            .sorted { ($0.element.status.rawValue, $0.offset) < ($1.element.status.rawValue, $1.offset) }
            .map(\.element)
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        let loc = Loc(nil)
        return DueEntry(date: .now, vehicle: .sample(loc), loc: loc)
    }

    func snapshot(for configuration: SelectVehicleIntent, in context: Context) async -> DueEntry {
        let entry = makeEntry(configuration, snapshot: WidgetSnapshot.load(), date: .now)
        return entry.vehicle == nil && context.isPreview ? placeholder(in: context) : entry
    }

    /// One entry now and one per midnight for a week, so date-based items turn due without opening the app.
    func timeline(for configuration: SelectVehicleIntent, in context: Context) async -> Timeline<DueEntry> {
        let snapshot = WidgetSnapshot.load()
        let today = Calendar.current.startOfDay(for: .now)
        var entries = [makeEntry(configuration, snapshot: snapshot, date: .now)]
        for i in 1...7 {
            if let day = Calendar.current.date(byAdding: .day, value: i, to: today) {
                entries.append(makeEntry(configuration, snapshot: snapshot, date: day))
            }
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeEntry(_ configuration: SelectVehicleIntent, snapshot: WidgetSnapshot?, date: Date) -> DueEntry {
        let vehicles = snapshot?.vehicles ?? []
        // Overdue items weigh more than due-soon ones; ties keep the app's order.
        let score: (WidgetSnapshot.VehicleSummary) -> Int = { v in
            v.items.reduce(0) { sum, item in
                switch item.status(on: date) {
                case .overdue: sum + 1_000
                case .soon: sum + 1
                case .ok: sum
                }
            }
        }
        let best = vehicles.map(score).max()
        let vehicle = vehicles.first { $0.id == configuration.vehicle?.id } ?? vehicles.first { score($0) == best }
        return DueEntry(date: date, vehicle: vehicle, loc: Loc(snapshot))
    }
}

extension WidgetSnapshot.VehicleSummary {
    /// Example shown in the widget gallery before any vehicle is added, and in Xcode previews.
    static func sample(_ loc: Loc) -> WidgetSnapshot.VehicleSummary {
        WidgetSnapshot.VehicleSummary(
        id: UUID(), name: loc("My car"), symbol: "car.fill", km: 48_250,
        items: [
            .init(id: UUID(), title: loc("Engine oil"), symbol: "drop.fill", dueDate: nil, remainingKm: -300, soonKm: 1_000, soonDays: 30),
            .init(id: UUID(), title: loc("Brake fluid"), symbol: "exclamationmark.brakesignal",
                  dueDate: Calendar.current.date(byAdding: .day, value: 12, to: .now), remainingKm: nil, soonKm: 1_000, soonDays: 30),
            .init(id: UUID(), title: loc("Air filter"), symbol: "aqi.medium", dueDate: nil, remainingKm: 6_200, soonKm: 1_000, soonDays: 30),
        ])
    }
}

// MARK: - Views

struct ServiceBookWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        if let vehicle = entry.vehicle {
            let rows = entry.rows
            switch family {
            case .accessoryInline:
                Text(verbatim: "\(vehicle.name) · \(summaryText(rows))")
            case .accessoryRectangular:
                rectangular(vehicle, rows)
            case .systemSmall:
                small(vehicle, rows)
            default:
                list(vehicle, rows, max: family == .systemLarge ? 8 : 3)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "car.2.fill").font(.title2).foregroundStyle(.tint)
                Text(verbatim: entry.loc("Open ServiceBook to add a vehicle."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func color(_ status: ItemStatus) -> Color {
        switch status {
        case .overdue: .red
        case .soon: .orange
        case .ok: .secondary
        }
    }

    private func summaryText(_ rows: [DueRow]) -> String {
        let overdue = rows.filter { $0.status == .overdue }.count
        let soon = rows.filter { $0.status == .soon }.count
        if overdue > 0 { return entry.loc("%lld overdue", overdue) }
        if soon > 0 { return entry.loc("%lld due soon", soon) }
        return entry.loc("All up to date")
    }

    /// Only the most important of the summary labels.
    @ViewBuilder
    private func mainLabel(_ rows: [DueRow]) -> some View {
        let overdue = rows.filter { $0.status == .overdue }.count
        let soon = rows.filter { $0.status == .soon }.count
        if overdue > 0 {
            Label(entry.loc("%lld overdue", overdue), systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else if soon > 0 {
            Label(entry.loc("%lld due soon", soon), systemImage: "clock.fill").foregroundStyle(.orange)
        } else {
            Label(entry.loc("All up to date"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private func summary(_ rows: [DueRow]) -> some View {
        let overdue = rows.filter { $0.status == .overdue }.count
        let soon = rows.filter { $0.status == .soon }.count
        if overdue > 0 {
            Label(entry.loc("%lld overdue", overdue), systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
        if soon > 0 {
            Label(entry.loc("%lld due soon", soon), systemImage: "clock.fill").foregroundStyle(.orange)
        }
        if overdue == 0 && soon == 0 {
            Label(entry.loc("All up to date"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func small(_ vehicle: WidgetSnapshot.VehicleSummary, _ rows: [DueRow]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: vehicle.symbol).font(.title3).foregroundStyle(.tint)
            Text(verbatim: vehicle.name).font(.headline).lineLimit(1)
            Text(verbatim: entry.loc.km(vehicle.km)).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            mainLabel(rows).font(.caption.weight(.semibold)).lineLimit(1)
            if let first = rows.first {
                Text(verbatim: first.item.title).font(.caption2).lineLimit(1)
                Text(verbatim: first.item.dueText(on: entry.date, entry.loc))
                    .font(.caption2).foregroundStyle(color(first.status)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func list(_ vehicle: WidgetSnapshot.VehicleSummary, _ rows: [DueRow], max: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: vehicle.symbol).foregroundStyle(.tint)
                Text(verbatim: vehicle.name).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: entry.loc.km(vehicle.km)).font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty || family == .systemLarge {
                HStack(spacing: 10) { summary(rows) }.font(.caption.weight(.semibold))
            }
            ForEach(rows.prefix(max)) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.item.symbol).font(.caption).foregroundStyle(color(row.status)).frame(width: 18)
                    Text(verbatim: row.item.title).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: row.item.dueText(on: entry.date, entry.loc))
                        .font(.caption).foregroundStyle(color(row.status)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func rectangular(_ vehicle: WidgetSnapshot.VehicleSummary, _ rows: [DueRow]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(vehicle.name, systemImage: vehicle.symbol).font(.headline).widgetAccentable().lineLimit(1)
            Text(verbatim: summaryText(rows)).lineLimit(1)
            if let first = rows.first {
                Text(verbatim: "\(first.item.title) · \(first.item.dueText(on: entry.date, entry.loc))")
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct MaintenanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MaintenanceWidget", intent: SelectVehicleIntent.self, provider: Provider()) { entry in
            ServiceBookWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("ServiceBook")
        .description("Maintenance due for your vehicle.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ServiceBookWidgetBundle: WidgetBundle {
    var body: some Widget {
        MaintenanceWidget()
    }
}

#Preview(as: .systemSmall) {
    MaintenanceWidget()
} timeline: {
    DueEntry(date: .now, vehicle: .sample(Loc(nil)), loc: Loc(nil))
}

#Preview(as: .systemMedium) {
    MaintenanceWidget()
} timeline: {
    DueEntry(date: .now, vehicle: .sample(Loc(nil)), loc: Loc(nil))
}

#Preview(as: .accessoryRectangular) {
    MaintenanceWidget()
} timeline: {
    DueEntry(date: .now, vehicle: .sample(Loc(nil)), loc: Loc(nil))
}
