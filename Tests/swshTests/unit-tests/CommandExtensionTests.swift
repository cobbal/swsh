@testable import swsh
import XCTest

class CommandExtensionTests: XCTestCase {
    let cmd = MockCommand()

    var str = "hello\n"
    var data: Data { str.data(using: .utf8)! }

    func withResult<T>(_ cmd: MockCommand, block: () -> T) -> (MockCommand.Result, T) {
        var result: MockCommand.Result?
        cmd.resultCallback = { result = $0 }
        let blockResult = block()
        cmd.resultCallback = nil
        return (result!, blockResult)
    }

    func withAsyncResult(
        _ cmd: MockCommand,
        _ runnerBlock: @escaping (MockCommand) throws -> Void,
        _ resultBlock: @escaping (MockCommand.Result) -> Void
    ) {
        let finish = XCTestExpectation()

        cmd.resultCallback = {
            resultBlock($0)
        }
        DispatchQueue.global().async {
            try! XCTAssertNoThrow(runnerBlock(cmd))
            finish.fulfill()
        }
        wait(for: [finish], timeout: 1)
        cmd.resultCallback = nil
    }

    func withAsyncEcho(_ cmd: MockCommand, fds: [Int32] = [1], block: @escaping (MockCommand) throws -> Void) {
        withAsyncResult(cmd, block) { res in
            for fd in fds {
                res[fd].write(self.data)
                res[fd].closeFile()
            }
            res.setExit(code: 0)
        }
    }

    func testAsync() throws {
        let res = try unwrap(cmd.async(stdin: 4, stdout: 5, stderr: 6) as? MockCommand.Result)
        XCTAssertEqual(res.fdMap.map { $0.src }, [4, 5, 6])
        XCTAssertEqual(res.fdMap.map { $0.dst }, [0, 1, 2])
    }

    func testAsyncStream() {
        let (res, handle) = withResult(cmd) { cmd.asyncStream() }
        res[1].write(data)
        res[2].write(data)
        res[1].closeFile()
        res[2].closeFile()
        XCTAssertEqual(handle.readDataToEndOfFile(), data)
    }

    func testAsyncStreamJoin() {
        let (res, handle) = withResult(cmd) { cmd.asyncStream(joinErr: true) }
        res[1].write(data)
        res[2].write(data)
        res[1].closeFile()
        res[2].closeFile()
        XCTAssertEqual(handle.readDataToEndOfFile(), data + data)
    }

    func testRunSucceeds() {
        withAsyncResult(cmd, {
            try $0.run()
        }, { res in
            res.setExit(code: 0)
        })
    }

    func testRunBoolTrue() {
        withAsyncResult(cmd, {
            XCTAssertTrue($0.runBool())
        }, { res in
            res.setExit(code: 0)
        })
    }

    func testRunBoolFalse() {
        withAsyncResult(cmd, {
            XCTAssertFalse($0.runBool())
        }, { res in
            res.setExit(code: 42)
        })
    }

    func testRunFile() {
        withAsyncEcho(cmd) {
            let url = try $0.runFile()
            XCTAssertEqual(try Data(contentsOf: url), self.data)
        }
    }

    func testRunData() {
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runData(), self.data)
        }
    }

    func testRunDataJoin() {
        withAsyncEcho(cmd, fds: [1, 2]) {
            XCTAssertEqual(try $0.runData(joinErr: true), self.data + self.data)
        }
    }

    func testRunString() {
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runString(), "hello")
        }
    }

    func testRunStringJoin() {
        withAsyncEcho(cmd, fds: [1, 2]) {
            XCTAssertEqual(try $0.runString(joinErr: true), "hello\nhello")
        }
    }

    func testRunStringBlank() {
        str = "\n\n"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runString(), "")
        }
    }

    func testRunStringBadEncoding() {
        str = "Ünicode"
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runString(encoding: .nonLossyASCII))
        }
    }

    func testRunLines() {
        str = "a\nb\n\nc\n\n"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runLines(), ["a", "b", "", "c"])
        }
    }

    func testRunJson() {
        str = "{\"x\": [1, 2]}"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runJson() as? [String: [Int]], ["x": [1, 2]])
        }
    }

    func testInvalidJson() {
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runJson())
        }
    }

    func testJsonDecodable() {
        str = "{\"x\": [1, 2]}"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runJson([String: [Int]].self), ["x": [1, 2]])
        }
    }

    func testInvalidJsonDecodable() {
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runJson(Int.self))
        }
    }
}
