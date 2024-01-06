import swsh
import XCTest

final class AsyncIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalCommand.verbose = true
    }

    func testRunStringSucceeds() async throws {
        for newlines in ["", "\n", "\\n", "\\n\\n"] {
            let result = try await cmd("printf", "%s %s\(newlines)", "hello,", "world!").runString()
            XCTAssertEqual(result, "hello, world!" )
        }
    }

    func testPipes() async throws {
        try await Pipeline(cmd("echo", "foo"), cmd("cat"), cmd("cat")).run()
    }

    func testRunBoolTrue() async {
        let result = await cmd("true").runBool()
        XCTAssertTrue(result)
    }

    func testRunBoolFalse() async {
        let result = await cmd("false").runBool()
        XCTAssertFalse(result)
    }

    func testFalseRun() async {
        await XCTAssertThrowsAsyncError(try await cmd("false").run()) { error in
            XCTAssertEqual("\(error)", "command \"false\" failed with exit code 1")
        }
    }

    func testPipeFailFails() async {
        let result0 = await (cmd("false") | cmd("true")).runBool()
        let result1 = await (cmd("true") | cmd("false")).runBool()
        XCTAssertFalse(result0)
        XCTAssertFalse(result1)
    }
}
