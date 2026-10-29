import XCTest
@testable import ServiceBook

final class OnDeviceReaderTests: XCTestCase {

    func testShortDocumentIsReadWhole() {
        let pages = ["Engine oil | replace | 6,000 km", "", "Brake fluid | replace | 24 months"]
        let chunks = OnDeviceImporter.chunks(from: pages)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].pages, [0, 2])
        XCTAssertTrue(chunks[0].text.contains("[page 3]"))
    }

    func testLongManualKeepsMaintenancePages() {
        var pages = Array(repeating: "Radio and seat adjustment. Welcome to your new vehicle.", count: 40)
        pages[30] = "PERIODIC MAINTENANCE CHART\nEngine oil | replace | every 12,000 km or 12 months"
        pages[31] = "Maintenance (continued)\nSpark plugs | replace | 24,000 km"
        let chunks = OnDeviceImporter.chunks(from: pages)
        XCTAssertEqual(chunks.flatMap(\.pages), [30, 31])
        XCTAssertEqual(chunks.first?.label, "31–32")
    }

    func testChunksStayWithinSize() {
        let page = (1...400).map { "Line \($0): inspect and adjust the chain slack every 1,000 km" }.joined(separator: "\n")
        let chunks = OnDeviceImporter.chunks(from: [page], size: 3000)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 3000 + 20 })
        XCTAssertTrue(OnDeviceImporter.split(String(repeating: "x", count: 7000), size: 3000).allSatisfy { $0.count <= 3000 })
    }

    func testMergeKeepsMostCompleteDuplicate() {
        let merged = OnDeviceImporter.merge([
            ["title": "Engine oil", "action": "replace", "intervalKm": 6000],
            ["title": "Air filter", "action": "clean", "intervalKm": 6000],
            ["title": "Engine Oil", "action": "replace", "intervalKm": 6000, "intervalMonths": 12],
            ["title": "Engine oil", "action": "check", "intervalKm": 1000],
        ])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0]["intervalMonths"] as? Int, 12)
        XCTAssertEqual(merged.map { $0["action"] as? String }, ["replace", "clean", "check"])
    }

    func testMergedItemsDecodeAsSchedule() throws {
        let envelope: [String: Any] = ["make": "Kawasaki", "model": "Z400", "summary": "",
                                       "tasks": OnDeviceImporter.merge([["title": "Engine oil", "action": "replace",
                                                                         "category": "oil", "intervalKm": 12000]])]
        let vehicle = ManualImporter.VehicleDescription(make: "Kawasaki", model: "Z400", year: 2021, variant: "",
                                                        fuel: "petrol", kind: "motorcycle")
        let result = try ManualImporter.decode(JSONSerialization.data(withJSONObject: envelope), vehicle: vehicle,
                                               usage: AIUsage(), model: "on-device")
        XCTAssertEqual(result.template.tasks.first?.intervalKm, 12000)
    }

    func testOCRLinesKeepTableRowsTogether() {
        // Vision boxes: origin bottom left, so higher y comes first.
        let text = PageText.lines(from: [
            (CGRect(x: 0.6, y: 0.80, width: 0.2, height: 0.02), "12,000 km"),
            (CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.03), "Maintenance chart"),
            (CGRect(x: 0.1, y: 0.801, width: 0.3, height: 0.02), "Engine oil"),
            (CGRect(x: 0.1, y: 0.75, width: 0.3, height: 0.02), "Spark plugs"),
        ])
        XCTAssertEqual(text, "Maintenance chart\nEngine oil | 12,000 km\nSpark plugs")
    }

    func testParseOpenModelReply() {
        let reply = """
        <think>
        </think>
        ```json
        {"tasks":[{"title":"Olio motore","action":"replace","category":"oil","intervalKm":20000,"intervalMonths":12},
                  {"title":"Liquido freni","action":"replace","category":"brakes","intervalMonths":"24"},
                  {"title":"Avvertenza","action":"check","category":"general"}],
         "specs":[{"group":"Fluids","title":"Olio motore","value":"SAE 5W-30, 3,8 L"}]}
        ```
        """
        let found = MLXImporter.parse(reply, source: "Manual p. 112")
        XCTAssertEqual(found.items.count, 2)   // the item without an interval is dropped
        XCTAssertEqual(found.items.first?["sourceRef"] as? String, "Manual p. 112")
        XCTAssertEqual(found.specs.count, 1)
        XCTAssertTrue(MLXImporter.parse("no JSON here", source: "").items.isEmpty)
    }
}
