import XCTest
import SwiftData
@testable import ServiceBook

@MainActor
final class ScheduleTests: XCTestCase {

    /// The catalog published on GitHub (catalog/ in the repo), read from this checkout.
    private var catalogDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("catalog")
    }

    private func loadIndex() throws -> CatalogIndex {
        try JSONDecoder().decode(CatalogIndex.self, from: Data(contentsOf: catalogDir.appendingPathComponent("index.json")))
    }

    /// Every catalog file decodes, agrees with the index, has intervals, and carries a translation of every text.
    func testCatalogSchedules() throws {
        let index = try loadIndex()
        XCTAssertGreaterThan(index.schedules.count, 50)
        XCTAssertEqual(Set(index.schedules.map(\.id)).count, index.schedules.count, "duplicate ids")
        for e in index.schedules {
            let data = try Data(contentsOf: catalogDir.appendingPathComponent("schedules/\(e.id).json"))
            let t = try JSONDecoder().decode(ScheduleTemplate.self, from: data)
            XCTAssertEqual(t.id, e.id)
            XCTAssertEqual(t.tasks.count, e.tasks, e.id)
            XCTAssertEqual(t.specs?.count ?? 0, e.specs, e.id)
            XCTAssertEqual(t.version ?? 0, e.version, e.id)
            XCTAssertFalse(t.tasks.isEmpty, e.id)
            var texts = [t.model, t.source, t.disclaimer, t.generation].compactMap { $0 }
            texts += t.tasks.flatMap { [$0.title, $0.notes, $0.spec, $0.sourceRef].compactMap { $0 } }
            texts += (t.specs ?? []).flatMap { [$0.group, $0.title, $0.value] }
            for task in t.tasks {
                XCTAssertTrue(task.intervalKm != nil || task.intervalMonths != nil || task.firstKm != nil || task.firstMonths != nil,
                              "\(t.id): \(task.title) has no interval")
                XCTAssertNotNil(TaskAction(rawValue: task.actionRaw ?? ""), "\(t.id): \(task.title)")
            }
            for lang in ["it", "fr", "es", "pt"] {
                for text in texts {
                    XCTAssertNotNil(t.translations?[lang]?[text], "\(t.id) \(lang): \(text)")
                }
                for text in [e.model, e.generation].compactMap({ $0 }) {
                    XCTAssertNotNil(index.translations?[lang]?[text], "index \(lang): \(text)")
                }
            }
        }
    }

    func testMatching() throws {
        let lib = ScheduleLibrary.shared
        lib.entries = try loadIndex().schedules
        func best(_ make: String, _ model: String, _ year: Int, _ fuel: FuelType, _ kind: VehicleKind) -> String? {
            lib.matches(make: make, model: model, year: year, fuel: fuel, kind: kind).first?.id
        }
        XCTAssertEqual(best("Kawasaki", "Z400", 2021, .petrol, .motorcycle), "kawasaki-z400-2019")
        XCTAssertEqual(best("Ford", "Fiesta", 2018, .diesel, .car), "ford-fiesta-mk8-diesel")
        XCTAssertEqual(best("Ford", "Fiesta Mk7", 2015, .petrol, .car), "ford-fiesta-mk7-petrol")
        XCTAssertEqual(best("VW", "Golf 8 1.5 eTSI", 2022, .petrol, .car), "volkswagen-golf-8-petrol")
        XCTAssertEqual(best("Škoda", "Superb", 2020, .diesel, .car), "skoda-generic-diesel")
        XCTAssertEqual(best("Citroen", "C3", 2019, .petrol, .car), "citroen-c3-petrol")
        XCTAssertEqual(best("BMW", "R 1300 GS Adventure", 2025, .petrol, .motorcycle), "bmw-r1300gs")
        XCTAssertEqual(best("BMW", "320d", 2021, .diesel, .car), "bmw-3-series-g20-diesel")
        XCTAssertEqual(best("Honda", "CB500F", 2022, .petrol, .motorcycle), "honda-cb500-family")
        XCTAssertEqual(best("Honda", "CB1000 Hornet", 2025, .petrol, .motorcycle), "honda-generic-motorcycle")
        XCTAssertEqual(best("Toyota", "Yaris Cross", 2023, .hybrid, .car), "toyota-yaris-cross-hybrid")
        XCTAssertEqual(best("Yamaha", "MT-07", 2023, .petrol, .motorcycle), "yamaha-mt07")
        // A motorcycle make doesn't match a car, and an unknown make matches nothing.
        XCTAssertTrue(lib.matches(make: "Honda", model: "Civic", year: 2020, fuel: .petrol, kind: .car).isEmpty)
        XCTAssertTrue(lib.matches(make: "Lada", model: "Niva", year: 2020, fuel: .petrol, kind: .car).isEmpty)
    }

    private func makeVehicle() throws -> (ModelContext, Vehicle, MaintenanceTask) {
        let container = try ModelContainer(for: Vehicle.self, MaintenanceTask.self, ServiceRecord.self,
                                           OdometerReading.self, SpecNote.self, Attachment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let v = Vehicle(name: "", make: "Kawasaki", modelName: "Z400", year: 2020, kind: .motorcycle, fuel: .petrol)
        v.firstRegistration = Date()
        context.insert(v)
        let t = MaintenanceTask(title: "Engine oil", action: .replace, category: "oil")
        t.intervalKm = 12_000
        t.intervalMonths = 12
        context.insert(t)
        t.vehicle = v
        return (context, v, t)
    }

    private func setKm(_ km: Int, _ v: Vehicle, _ context: ModelContext) {
        let r = OdometerReading(km: km)
        context.insert(r)
        r.vehicle = v
    }

    func testDueByKilometres() throws {
        let (context, v, t) = try makeVehicle()
        setKm(5_000, v, context)
        XCTAssertEqual(t.dueInfo(v.dueState).status, .upcoming)
        XCTAssertEqual(t.dueInfo(v.dueState).dueKm, 12_000)

        setKm(11_500, v, context)
        XCTAssertEqual(t.dueInfo(v.dueState).status, .dueSoon)

        setKm(12_100, v, context)
        XCTAssertEqual(t.dueInfo(v.dueState).status, .overdue)

        let record = ServiceRecord(date: Date(), title: "Oil change")
        record.odometerKm = 12_100
        context.insert(record)
        record.vehicle = v
        record.tasks = [t]
        let info = t.dueInfo(v.dueState)
        XCTAssertEqual(info.status, .upcoming)
        XCTAssertEqual(info.dueKm, 24_100)
    }

    func testDueByTimeAndBaseline() throws {
        let (context, v, t) = try makeVehicle()
        v.firstRegistration = Calendar.current.date(byAdding: .month, value: -13, to: Date())
        setKm(3_000, v, context)
        XCTAssertEqual(t.dueInfo(v.dueState).status, .overdue)   // 12 months passed

        // History unknown: count from today instead.
        v.baselineKm = 3_000
        v.baselineDate = Date()
        let info = t.dueInfo(v.dueState)
        XCTAssertEqual(info.status, .upcoming)
        XCTAssertEqual(info.dueKm, 15_000)
    }

    func testOneTimeItem() throws {
        let (context, v, _) = try makeVehicle()
        let run = MaintenanceTask(title: "Run-in service", action: .service, category: "service")
        run.oneTime = true
        run.firstKm = 1_000
        context.insert(run)
        run.vehicle = v
        setKm(900, v, context)
        XCTAssertEqual(run.dueInfo(v.dueState).status, .dueSoon)
        v.baselineKm = 8_000
        v.baselineDate = Date()
        XCTAssertEqual(run.dueInfo(v.dueState).status, .completed)
    }
}
