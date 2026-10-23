import Foundation
import SwiftData

// MARK: - Enums (stored as raw strings for SwiftData robustness)

enum VehicleKind: String, CaseIterable, Identifiable {
    case car, motorcycle, scooter, van, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .car: L("Car")
        case .motorcycle: L("Motorcycle")
        case .scooter: L("Scooter")
        case .van: L("Van")
        case .other: L("Other")
        }
    }
    var symbol: String {
        switch self {
        case .car: "car.fill"
        case .motorcycle: "motorcycle"
        case .scooter: "scooter"
        case .van: "bus.fill"
        case .other: "wrench.and.screwdriver.fill"
        }
    }
}

enum FuelType: String, CaseIterable, Identifiable {
    case petrol, diesel, hybrid, electric, other
    var id: String { rawValue }
    var label: String { L(rawValue.capitalized) }
}

enum TaskAction: String, CaseIterable, Identifiable {
    case inspect, check, replace, lubricate, clean, adjust, service
    var id: String { rawValue }
    var label: String { L(rawValue.capitalized) }
}

enum RecordKind: String, CaseIterable, Identifiable {
    case service, tyres, part, repair, inspection, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .service: L("Service / maintenance")
        case .tyres: L("Tyre change")
        case .part: L("Part replacement")
        case .repair: L("Repair")
        case .inspection: L("Inspection / test")
        case .other: L("Other")
        }
    }
    var symbol: String {
        switch self {
        case .service: "wrench.and.screwdriver"
        case .tyres: "circle.circle"
        case .part: "gearshape.2"
        case .repair: "hammer"
        case .inspection: "checkmark.seal"
        case .other: "doc.text"
        }
    }
}

enum TaskCategory {
    static func symbol(for category: String) -> String {
        switch category {
        case "oil": "drop.fill"
        case "filters": "aqi.medium"
        case "brakes": "exclamationmark.brakesignal"
        case "tyres", "wheels": "circle.circle"
        case "chain": "link"
        case "cooling": "thermometer.snowflake"
        case "fuel": "fuelpump.fill"
        case "ignition", "electrical": "bolt.fill"
        case "engine": "engine.combustion.fill"
        case "suspension", "steering": "arrow.up.and.down.and.arrow.left.and.right"
        case "transmission": "gearshape.2.fill"
        case "climate": "snowflake"
        case "legal": "checkmark.seal.fill"
        case "safety": "cross.case.fill"
        case "owner": "eye.fill"
        case "service": "wrench.and.screwdriver.fill"
        case "emissions": "smoke.fill"
        case "controls": "slider.horizontal.3"
        case "body", "chassis": "car.side"
        default: "wrench.fill"
        }
    }
}

// MARK: - Vehicle

@Model
final class Vehicle {
    var id: UUID = UUID()
    var name: String = ""
    var make: String = ""
    var modelName: String = ""
    var year: Int = 0
    var variant: String = ""
    var kindRaw: String = VehicleKind.car.rawValue
    var fuelRaw: String = FuelType.petrol.rawValue
    var plate: String = ""
    var vin: String = ""
    var firstRegistration: Date?
    var notes: String = ""
    var scheduleSource: String = ""
    var scheduleSourceURLs: [String] = []
    var scheduleDisclaimer: String = ""
    var createdAt: Date = Date()
    /// "History unknown": items never logged are counted from this point instead of from new.
    var baselineKm: Int?
    var baselineDate: Date?
    @Attribute(.externalStorage) var photo: Data?

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceTask.vehicle)
    var tasks: [MaintenanceTask] = []
    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.vehicle)
    var records: [ServiceRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \OdometerReading.vehicle)
    var readings: [OdometerReading] = []
    @Relationship(deleteRule: .cascade, inverse: \SpecNote.vehicle)
    var specs: [SpecNote] = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.vehicle)
    var documents: [Attachment] = []

    init(name: String, make: String, modelName: String, year: Int, kind: VehicleKind, fuel: FuelType) {
        self.name = name
        self.make = make
        self.modelName = modelName
        self.year = year
        self.kindRaw = kind.rawValue
        self.fuelRaw = fuel.rawValue
    }

    var kind: VehicleKind {
        get { VehicleKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var fuel: FuelType {
        get { FuelType(rawValue: fuelRaw) ?? .other }
        set { fuelRaw = newValue.rawValue }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        return [make, modelName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var subtitle: String {
        var parts: [String] = []
        if year > 0 { parts.append(String(year)) }
        if !variant.isEmpty { parts.append(variant) }
        if !plate.isEmpty { parts.append(plate) }
        return parts.joined(separator: " · ")
    }

    /// Highest known odometer value, from mileage readings and service records.
    var currentKm: Int {
        let r = readings.map(\.km).max() ?? 0
        let s = records.compactMap(\.odometerKm).max() ?? 0
        return max(r, s)
    }

    /// Reference date for items that have never been done (first registration, else creation date).
    var startDate: Date { firstRegistration ?? createdAt }

    var dueState: DueState {
        DueState(currentKm: currentKm, startDate: startDate, baselineKm: baselineKm, baselineDate: baselineDate)
    }

    func statusCounts() -> (overdue: Int, soon: Int) {
        let state = dueState
        let now = Date()
        var overdue = 0, soon = 0
        for t in tasks where t.isEnabled {
            switch t.dueInfo(state, now: now).status {
            case .overdue: overdue += 1
            case .dueSoon: soon += 1
            default: break
            }
        }
        return (overdue, soon)
    }
}

// MARK: - Maintenance item from the schedule

@Model
final class MaintenanceTask {
    var id: UUID = UUID()
    var title: String = ""
    var actionRaw: String = TaskAction.inspect.rawValue
    var category: String = "general"
    var intervalKm: Int?
    var intervalMonths: Int?
    var firstKm: Int?
    var firstMonths: Int?
    var oneTime: Bool = false
    var notes: String = ""
    var spec: String = ""
    var sourceRef: String = ""
    var isCustom: Bool = false
    var isEnabled: Bool = true
    var sortOrder: Int = 0
    var vehicle: Vehicle?
    @Relationship(inverse: \ServiceRecord.tasks)
    var records: [ServiceRecord] = []

    init(title: String, action: TaskAction = .inspect, category: String = "general") {
        self.title = title
        self.actionRaw = action.rawValue
        self.category = category
    }

    var action: TaskAction {
        get { TaskAction(rawValue: actionRaw) ?? .inspect }
        set { actionRaw = newValue.rawValue }
    }

    var intervalText: String {
        if oneTime {
            var parts: [String] = []
            if let k = firstKm { parts.append(L("at %@", Fmt.km(k))) }
            if let m = firstMonths { parts.append(Fmt.months(m)) }
            return L("Once, %@", parts.joined(separator: " \(L("or")) "))
        }
        var parts: [String] = []
        if let k = intervalKm { parts.append(Fmt.km(k)) }
        if let m = intervalMonths { parts.append(Fmt.months(m)) }
        if parts.isEmpty { return L("No interval") }
        return L("Every %@", parts.joined(separator: " \(L("or")) "))
    }

    var lastRecord: ServiceRecord? {
        records.max { $0.date < $1.date }
    }
}

// MARK: - Log entries

@Model
final class ServiceRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var odometerKm: Int?
    var title: String = ""
    var kindRaw: String = RecordKind.service.rawValue
    var notes: String = ""
    var cost: Double?
    var currencyCode: String = "EUR"
    var shop: String = ""
    /// Part / tyre details (e.g. tyre position, brand & model, size or part number, DOT code).
    var partPosition: String = ""
    var partBrand: String = ""
    var partSize: String = ""
    var partDetails: String = ""
    var vehicle: Vehicle?
    var tasks: [MaintenanceTask] = []
    @Relationship(deleteRule: .cascade, inverse: \Attachment.record)
    var attachments: [Attachment] = []

    init(date: Date = Date(), title: String = "", kind: RecordKind = .service) {
        self.date = date
        self.title = title
        self.kindRaw = kind.rawValue
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if tasks.count == 1, let t = tasks.first { return t.title }
        return kind.label
    }
}

@Model
final class OdometerReading {
    var id: UUID = UUID()
    var date: Date = Date()
    var km: Int = 0
    var note: String = ""
    var vehicle: Vehicle?

    init(date: Date = Date(), km: Int, note: String = "") {
        self.date = date
        self.km = km
        self.note = note
    }
}

@Model
final class SpecNote {
    var id: UUID = UUID()
    var group: String = "Notes"
    var title: String = ""
    var value: String = ""
    var sortOrder: Int = 0
    var vehicle: Vehicle?

    init(group: String, title: String, value: String, sortOrder: Int = 0) {
        self.group = group
        self.title = title
        self.value = value
        self.sortOrder = sortOrder
    }
}

@Model
final class Attachment {
    var id: UUID = UUID()
    var filename: String = ""
    var typeIdentifier: String = "com.adobe.pdf"
    var label: String = ""
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var data: Data = Data()
    var vehicle: Vehicle?
    var record: ServiceRecord?

    init(filename: String, typeIdentifier: String, data: Data, label: String = "") {
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.label = label
    }

    var isPDF: Bool { typeIdentifier == "com.adobe.pdf" || filename.lowercased().hasSuffix(".pdf") }
    var displayName: String { label.isEmpty ? filename : label }
}

// MARK: - Formatting helpers

enum Fmt {
    static func km(_ value: Int) -> String {
        value.formatted(.number.locale(AppLanguage.locale)) + " km"
    }

    static func months(_ m: Int) -> String {
        m % 12 == 0 ? L("%lld years", m / 12) : L("%lld months", m)
    }

    static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLanguage.locale))
    }

    static func money(_ value: Double, code: String) -> String {
        value.formatted(.currency(code: code).locale(AppLanguage.locale))
    }
}
