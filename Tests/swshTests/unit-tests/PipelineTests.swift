@testable import swsh
import XCTest

class PipelineTests: XCTestCase {
    let cmd0 = MockCommand()
    let cmd1 = MockCommand()
    let cmd2 = MockCommand()

    lazy var pipeline = Pipeline(cmd0, cmd1, cmd2)

    func results() -> ([MockCommand.Result], Pipeline.Result) {
        let res = pipeline.coreAsync(fdMap: []) as! Pipeline.Result
        return (res.results as! [MockCommand.Result], res)
    }

    func testPipeFail0() {
        let (subs, res) = results()
        subs[0].setExit(code: 42)
        subs[1].setExit(code: 50)
        subs[2].setExit(code: 0)
        XCTAssertEqual(res.exitCode(), 42)
    }

    func testPipeFail1() {
        let (subs, res) = results()
        subs[0].setExit(code: 0)
        subs[1].setExit(code: 42)
        subs[2].setExit(code: 50)
        XCTAssertEqual(res.exitCode(), 42)
    }

    func testPipeFail2() {
        let (subs, res) = results()
        subs[0].setExit(code: 0)
        subs[1].setExit(code: 0)
        subs[2].setExit(code: 42)
        XCTAssertEqual(res.exitCode(), 42)
    }

    func testPipeIsRunning() {
        let (subs, res) = results()
        XCTAssertTrue(res.isRunning)
        subs[0].setExit(code: 0)
        XCTAssertTrue(res.isRunning)
        subs[1].setExit(code: 0)
        XCTAssertTrue(res.isRunning)
        subs[2].setExit(code: 0)
        XCTAssertFalse(res.isRunning)
    }

    func testPipeSucceed() {
        let (subs, res) = results()
        subs.forEach { $0.setExit(code: 0) }
        XCTAssertNoThrow(try res.succeed())
    }

    func testPipeSucceedFails() {
        let (subs, res) = results()
        subs.forEach { $0.setExit(code: -1) }
        XCTAssertThrowsError(try res.succeed())
    }

    func testPipeSyntax() throws {
        let cmd0 = MockCommand()
        let cmd1 = MockCommand()

        let pipe = try unwrap(cmd0 | cmd1 as? Pipeline)

        XCTAssertEqual(pipe.first as? MockCommand, cmd0)
        XCTAssertEqual(pipe.rest as? [MockCommand], [cmd1])
    }
}
