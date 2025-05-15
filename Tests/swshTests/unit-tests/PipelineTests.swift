@testable import swsh
import XCTest

class PipelineTests: XCTestCase {
    let cmd0 = MockCommand(description: "cmd0")
    let cmd1 = MockCommand(description: "cmd1")
    let cmd2 = MockCommand(description: "cmd2")

    lazy var pipeline = Pipeline(cmd0, cmd1, cmd2)

    func results() -> ([MockCommand.Result], Pipeline.Result) {
        let res = pipeline.coreAsync(fdMap: [:]) as! Pipeline.Result
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
        let pipe = try unwrap(cmd0 | cmd1 as? Pipeline)

        XCTAssertEqual(pipe.first as? MockCommand, cmd0)
        XCTAssertEqual(pipe.rest as? [MockCommand], [cmd1])
    }

    func testPipeKillSuccess() throws {
        try pipeline.async().kill()
    }

    class AnError: Error, Equatable, CustomStringConvertible {
        static func == (lhs: AnError, rhs: AnError) -> Bool { lhs.id == rhs.id }
        let id = UUID()

        public var description: String {
            "AnError id: \(id)"
        }
    }

    func testPipeKillFailure() throws {
        let err0 = AnError()
        let err1 = AnError()
        let err2 = AnError()
        cmd0.killResponse = err0
        cmd1.killResponse = err1
        cmd2.killResponse = err2

        XCTAssertThrowsError(try pipeline.async().kill()) { error in
            XCTAssertEqual(error as? AnError, err0)
        }
    }

    func testPipeKillPartialSuccess() throws {
        let err0 = AnError()
        let err2 = AnError()
        cmd0.killResponse = err0
        cmd1.killResponse = nil
        cmd2.killResponse = err2

        try pipeline.async().kill()
    }

    func testPipeDescription() throws {
        XCTAssertEqual(pipeline.description, "cmd0 | cmd1 | cmd2")
    }
}
