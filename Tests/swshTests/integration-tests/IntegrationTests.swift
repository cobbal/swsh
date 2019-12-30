@testable import swsh
import XCTest

final class IntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalCommand.verbose = true
    }

    func testRunStringSucceeds() {
        for newlines in ["", "\n", "\\n", "\\n\\n"] {
            XCTAssertEqual(
                try! cmd("printf", "%s %s\(newlines)", "hello,", "world!").runString(),
                "hello, world!")
        }
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

    func testFalseRun() {
        XCTAssertThrowsError(try cmd("false").run()) { error in
            XCTAssertEqual("\(error)", "command \"false\" failed with exit code 256")
        }
    }

    func testPipeFailFails() {
        XCTAssertFalse((cmd("false") | cmd("true")).runBool())
        XCTAssertFalse((cmd("true") | cmd("false")).runBool())
    }

    func testAbsPath() {
        XCTAssertFalse(cmd("/usr/bin/false").runBool())
    }

    func testNonExistantProgram() {
        let binary = "/usr/bin/\(UUID())"
        XCTAssertThrowsError(try cmd(binary).run()) { error in
            XCTAssertEqual("\(error)", "launching \"\(binary)\" failed with error code 2: No such file or directory")
        }
    }

    func testNonExistantProgramInPipeline() {
        let binary = "/usr/bin/\(UUID())"
        XCTAssertFalse((cmd(binary) | cmd("cat")).runBool())
    }

    func testCmdArgList() throws {
        let args = ["%s, %s, %s\\n", "1", "2 3", "4"]
        let str = try cmd("printf", arguments: args).runString()
        XCTAssertEqual(str, "1, 2 3, 4")
    }

    func testFailureIsntRunning() {
        let binary = "/usr/bin/\(UUID())"
        let res = cmd(binary).async()
        XCTAssertFalse(res.isRunning)
        XCTAssert(res is Error)
    }

    func testIsRunning() throws {
        let pipe = Pipe()
        let proc = cmd("cat").async(stdin: pipe.fileHandleForReading.fileDescriptor)
        XCTAssertTrue(proc.isRunning)
        pipe.fileHandleForWriting.closeFile()
        try proc.succeed()
    }

    func testOverwriteEnv() throws {
        let unique = UUID().uuidString
        let res = try cmd("bash", "-c", "echo $USER", addEnv: ["USER": unique]).runString()
        XCTAssertEqual(res, unique)
    }
}
