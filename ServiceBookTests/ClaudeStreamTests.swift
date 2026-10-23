import XCTest
@testable import ServiceBook

final class ClaudeStreamTests: XCTestCase {

    private func feed(_ lines: [String]) -> (StreamAccumulator, [AIEvent]) {
        var acc = StreamAccumulator()
        var events: [AIEvent] = []
        for l in lines { events += acc.consume(line: l) }
        return (acc, events)
    }

    /// Web-search stream as documented at platform.claude.com/docs/en/build-with-claude/streaming.
    func testWebSearchStream() {
        let lines = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-5-5","stop_reason":null,"usage":{"input_tokens":25,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I'll search."}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\": \"z400 owner manual\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"A","url":"https://a.example","encrypted_content":"Ev0D","page_age":null},{"type":"web_search_result","title":"B","url":"https://b.example","encrypted_content":"Ev0E","page_age":null}]}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            "event: ping",
            #"data: {"type":"ping"}"#,
            #"data: {"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"Found it"}}"#,
            #"data: {"type":"content_block_delta","index":3,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://a.example","title":"A","encrypted_index":"x","cited_text":"oil"}}}"#,
            #"data: {"type":"content_block_stop","index":3}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":10682,"output_tokens":510,"server_tool_use":{"web_search_requests":1}}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        let (acc, events) = feed(lines)

        XCTAssertEqual(acc.stopReason, "end_turn")
        XCTAssertEqual(events, [.searching("z400 owner manual"), .results(2)])
        XCTAssertEqual(acc.usage, AIUsage(inputTokens: 10682, outputTokens: 510, webSearches: 1, webFetches: 0))
        XCTAssertEqual(acc.finalText, "Found it")
        XCTAssertEqual(acc.content.count, 4)
        // Server blocks are kept intact so they can be sent back on pause_turn.
        let result = acc.content[2]
        XCTAssertEqual(result["type"] as? String, "web_search_tool_result")
        XCTAssertEqual(((result["content"] as? [[String: Any]])?.first)?["encrypted_content"] as? String, "Ev0D")
        XCTAssertEqual((acc.content[1]["input"] as? [String: Any])?["query"] as? String, "z400 owner manual")
        XCTAssertEqual((acc.content[3]["citations"] as? [Any])?.count, 1)
    }

    func testToolInputStreamsAndCountsItems() {
        let lines = [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":100,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"submit_schedule","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"make\":\"Kawasaki\",\"model\":\"Z400\",\"summary\":\"ok\",\"tasks\":[{\"title\":\"Engine oil\",\"action\":\"replace\",\"category\":\"oil\",\"intervalKm\":12000}"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":",{\"title\":\"Chain\",\"action\":\"lubricate\",\"category\":\"chain\",\"intervalKm\":600}]}"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":80}}"#,
        ]
        let (acc, events) = feed(lines)
        XCTAssertEqual(events, [.writing(1), .writing(2)])
        let input = acc.toolInput(named: "submit_schedule")
        XCTAssertEqual(input?["make"] as? String, "Kawasaki")
        XCTAssertEqual((input?["tasks"] as? [Any])?.count, 2)
        XCTAssertNil(acc.toolInput(named: "other"))
    }

    func testErrorEventAndEmptyTextBlocksDropped() {
        let (acc, _) = feed([
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ])
        XCTAssertEqual(acc.errorType, "overloaded_error")
        XCTAssertTrue(acc.content.isEmpty)
        XCTAssertNil(acc.stopReason)
    }

    func testHTTPErrorMapping() {
        func body(_ msg: String) -> Data { Data(#"{"type":"error","error":{"type":"x","message":"\#(msg)"}}"#.utf8) }
        XCTAssertEqual(ClaudeClient.mapError(status: 401, body: body("invalid x-api-key"), model: "m"), .invalidKey)
        XCTAssertEqual(ClaudeClient.mapError(status: 400, body: body("Your credit balance is too low"), model: "m"), .noCredit)
        XCTAssertEqual(ClaudeClient.mapError(status: 404, body: body("model: foo"), model: "foo"), .modelUnavailable("foo"))
        XCTAssertEqual(ClaudeClient.mapError(status: 529, body: body("Overloaded"), model: "m"), .overloaded)
        XCTAssertTrue(ClaudeClient.mapError(status: 429, body: body("rate"), model: "m").isRetryable)
        XCTAssertFalse(ClaudeClient.mapError(status: 400, body: body("bad"), model: "m").isRetryable)
    }

    func testSubmitToolSchemaIsStrictCompatible() throws {
        let tool = ManualImporter.submitTool(strict: true)
        XCTAssertEqual(tool["strict"] as? Bool, true)
        // Must serialise to JSON for the request body.
        let data = try JSONSerialization.data(withJSONObject: tool)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"null\""), "strict schemas should avoid nullable unions")
        XCTAssertTrue(text.contains("\"additionalProperties\":false"))
    }

    func testDecodeToolInputWithLooseTypes() throws {
        let input: [String: Any] = [
            "make": "Ford", "model": "Fiesta", "summary": "Found the service booklet.",
            "tasks": [
                ["title": "Engine oil & filter", "action": "Replace", "category": "oil", "intervalKm": 20000, "intervalMonths": 12],
                ["title": "Timing belt", "action": "replace", "category": "engine", "intervalKm": "200,000 km", "intervalMonths": 120.0],
                ["title": " ", "action": "check", "category": "general"],
            ],
            "specs": [["group": "Fluids", "title": "Engine oil", "value": "0W-30"]],
        ]
        let outcome = ClaudeClient.Outcome(text: "", toolInput: input, usage: AIUsage(inputTokens: 5))
        let desc = ManualImporter.VehicleDescription(make: "Ford", model: "Fiesta", year: 2018, variant: "1.5 TDCi", fuel: "diesel", kind: "car")
        let r = try ManualImporter.result(from: outcome, vehicle: desc, model: "claude-sonnet-5-5")
        XCTAssertEqual(r.template.tasks.count, 2)          // blank title dropped
        XCTAssertEqual(r.template.tasks[1].intervalKm, 200_000)
        XCTAssertEqual(r.template.tasks[1].intervalMonths, 120)
        XCTAssertEqual(r.template.specs?.count, 1)
        XCTAssertEqual(r.usage.inputTokens, 5)
    }

    func testTextFallbackWithComments() throws {
        let text = """
        Here is the schedule:
        ```json
        { "make": "Kawasaki", "model": "Z400", "summary": "x", // comment
          "sourceURLs": ["https://example.com/manual.pdf"],
          "tasks": [ { "title": "Oil", "action": "replace", "category": "oil", "intervalKm": 12000 } ] }
        ```
        """
        let outcome = ClaudeClient.Outcome(text: text, toolInput: nil, usage: AIUsage())
        let desc = ManualImporter.VehicleDescription(make: "Kawasaki", model: "Z400", year: 2020, variant: "", fuel: "petrol", kind: "motorcycle")
        let r = try ManualImporter.result(from: outcome, vehicle: desc, model: "m")
        XCTAssertEqual(r.template.tasks.first?.intervalKm, 12000)
        XCTAssertEqual(r.template.sourceURLs?.first, "https://example.com/manual.pdf")
    }
}
