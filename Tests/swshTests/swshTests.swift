import XCTest
@testable import swsh

final class swshTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BasicCommand.verbose = true
    }

    func testRunStringSucceeds() {
        for newlines in ["", "\n", "\\n", "\\n\\n"] {
            XCTAssertEqual(
                try! cmd("printf", "%s %s\(newlines)", "hello,", "world!").runString(),
                "hello, world!")
        }
    }

    func testExample() {
        print(try! (cmd("ls", "-l", "-a") | cmd("wc", "-l")).runString())
//        print(try! BasicCommand("ls").runString())
    }

    func testPipes() {
        try! Pipeline(cmd("echo", "foo"), cmd("cat"), cmd("cat")).run()
    }

    func testRunBoolTrue() {
        XCTAssertTrue(cmd("true").runBool())
    }

    func testRunBoolFalse() {
        XCTAssertFalse(cmd("false").runBool())
    }

    func testPipeFailFails() {
        XCTAssertFalse((cmd("false") | cmd("cat")).runBool())
    }
}
