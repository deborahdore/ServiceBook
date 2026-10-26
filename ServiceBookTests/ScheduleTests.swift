import XCTest
import SwiftData
@testable import ServiceBook

@MainActor
final class ScheduleTests: XCTestCase {

    func testBundledSchedulesLoad() {
        let templates = ScheduleLibrary.shared.templates
        XCTAssertEqual(templates.count, 5)
        for t in templates {
            XCTAssertFalse(t.tasks.isEmpty, t.id)
            for task in t.tasks {
                XCTAssertTrue(task.intervalKm != nil || task.intervalMonths != nil || task.firstKm != nil || task.firstMonths != nil,
                              "\(t.id): \(task.title) has no interval")
            }
        }
    }

    /// Every text of the bundled schedules needs an entry in Schedules.xcstrings for each language.
    func testBundledSchedulesAreTranslated() throws {
        for lang in ["it", "fr", "es", "pt"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), lang)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for t in ScheduleLibrary.shared.templates {
                var texts = [t.source, t.disclaimer, t.generation].compactMap { $0 }
                texts += t.tasks.flatMap { [$0.title, $0.notes, $0.spec, $0.sourceRef].compactMap { $0 } }
                texts += (t.specs ?? []).flatMap { [$0.group, $0.title, $0.value] }
                for text in texts {
                    XCTAssertNotEqual(bundle.localizedString(forKey: text, value: "∅", table: "Schedules"), "∅", "\(lang): \(text)")
                }
            }
        }
    }

    func testMatching() {
        let lib = ScheduleLibrary.shared
        XCTAssertEqual(lib.matches(make: "Kawasaki", model: "Z400", year: 2021, fuel: .petrol).first?.id, "kawasaki-z400-2019")
        XCTAssertEqual(lib.matches(make: "Ford", model: "Fiesta", year: 2018, fuel: .diesel).first?.id, "ford-fiesta-mk8-diesel")
        XCTAssertEqual(lib.matches(make: "Ford", model: "Fiesta Mk7", year: 2015, fuel: .petrol).first?.id, "ford-fiesta-mk7-petrol")
        XCTAssertTrue(lib.matches(make: "Honda", model: "Civic", year: 2020, fuel: .petrol).isEmpty)
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
