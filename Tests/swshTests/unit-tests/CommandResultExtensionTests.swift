@testable import swsh
import XCTest

class CommandResultExtensionTests: XCTestCase {
    let res = MockCommand.Result(command: MockCommand(), fdMap: [])

    func testFinish() {
        res.setExit(code: 2)
        res.finish()
    }

    func testDefaultSucceed() {
        res.setExit(code: 0)
        XCTAssertNoThrow(try res.defaultSucceed())
    }

    func testDefaultSucceedFail() {
        res.setExit(code: 1)
        XCTAssertThrowsError(try res.defaultSucceed())
    }
}
