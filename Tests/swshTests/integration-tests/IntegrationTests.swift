import swsh
import XCTest
#if os(Windows)
import WinSDK
#endif

final class IntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalCommand.verbose = true
        #if os(Windows)
        ExternalCommand.supplementaryPath = ";C:\\Program Files\\Git\\usr\\bin"
        #endif
    }

    func testReadmeExamples() {
        let rot13 = cmd("tr", "a-z", "n-za-m")
        XCTAssertEqual(
            try! rot13.input("secret message").runString(),
            "frperg zrffntr")

        XCTAssertEqual(
            try! (rot13.input("secret") | rot13).runString(),
            "secret")
        XCTAssertEqual(
            try! (rot13 | rot13).input("secret").runString(),
            "secret")

//        XCTAssertEqual(
//            try! (cmd("ls") | cmd("sort", "-n")).runLines(),
//            ["1.sh", "9.sh", "10.sh"])

        XCTAssertEqual(
            ["hello", "world", ""].map { cmd("test", "-z", $0).runBool() },
            [false, false, true])

        XCTAssertThrowsError(try (cmd("false") | cmd("cat")).run())
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
            XCTAssertEqual("\(error)", "command \"false\" failed with exit code 1")
        }
    }

    func testPipeFailFails() {
        XCTAssertFalse((cmd("false") | cmd("true")).runBool())
        XCTAssertFalse((cmd("true") | cmd("false")).runBool())
    }

    func testAbsPath() {
        #if os(Windows)
        XCTAssertEqual(try? cmd("C:\\Windows\\System32\\cmd.exe", "/C", "ECHO 1").runString(), "1\r\n")
        #else
        XCTAssertTrue(cmd("/bin/sh", "-c", "true").runBool())
        #endif
    }

    func testNonExistantProgram() {
        let binary = "/usr/bin/\(UUID())"
        let expected = "launching \"\(binary)\" failed with error code 2: No such file or directory"
        XCTAssertThrowsError(try cmd(binary).run()) { error in
            XCTAssertEqual("\(error)", expected)
        }
        XCTAssertThrowsError(try cmd(binary).async().kill()) { error in
            XCTAssertEqual("\(error)", expected)
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
        let pipe = FDPipe()
        let proc = cmd("cat").async(stdin: pipe.fileHandleForReading.fileDescriptor)
        XCTAssertTrue(proc.isRunning)
        pipe.fileHandleForWriting.close()
        try proc.succeed()
    }

    func testOverwriteEnv() throws {
        let unique = UUID().uuidString
        let res = try cmd("bash", "-c", "echo $USER", addEnv: ["USER": unique]).runString()
        XCTAssertEqual(res, unique)
    }

    func testKillRunningProcess() throws {
        let res = cmd("bash", "-c", "while true; do sleep 1; done").async()
        Thread.sleep(forTimeInterval: 0.5)
        try res.kill()
        XCTAssertEqual(res.exitCode(), 1)
    }

    func testKillDeadProcess() throws {
        let res = cmd("true").async()
        try res.succeed()
        XCTAssertThrowsError(try res.kill()) { error in
            #if os(Windows)
            XCTAssertEqual("\(error)", "command \"taskkill.exe\" failed with exit code 128")
            #else
            XCTAssertEqual("\(error)", "kill failed with error code 3: No such process")
            #endif
        }
    }

    func testKillStop() throws {
        let res = try (cmd("bash", "-c", "while true; do sleep 1; done") | cmd("cat") | cmd("cat")).input("").async()
        Thread.sleep(forTimeInterval: 0.5)
        try res.kill(signal: SIGSTOP)
        XCTAssert(res.isRunning)
        try res.kill(signal: SIGKILL)
        XCTAssertEqual(res.exitCode(), 1)
    }

    func testCombineOutput() throws {
        let res = try cmd("bash", "-c", "echo out; echo error >&2").combineError.runString()
        XCTAssertEqual(res, "out\nerror")
    }

    func testRemapCycle() throws {
        let pipes = [FDPipe(), FDPipe()]
        let write = pipes.map { $0.fileHandleForWriting.fileDescriptor }
        
        let id = UUID().uuidString
        #if os(Windows)
        let cProgram = """
            #include <io.h>
            #include <string.h>

            int main(int argc, char** argv) {
                _write(\(write[0]), "stuff-to-a", strlen("stuff-to-a"));
                _write(\(write[1]), "stuff-to-b", strlen("stuff-to-b"));
                return 0;
            }

            """
        let cProgramFile = "writer-\(id).c"
        let cProgramExecutable = "writer-\(id).exe"
        #else
        let cProgram = """
            #include <unistd.h>
            #include <string.h>

            int main(int argc, char** argv) {
                write(\(write[0]), "stuff-to-a", strlen("stuff-to-a"));
                write(\(write[1]), "stuff-to-b", strlen("stuff-to-b"));
                return 0;
            }

            """
        let cProgramFile = "writer-\(id).c"
        let cProgramExecutable = "writer-\(id)"
        #endif
        
        try cmd("cat").input(cProgram).output(overwritingFile: cProgramFile).run()
        try cmd("clang", "-o", cProgramExecutable, cProgramFile).run()

        let res = cmd("./\(cProgramExecutable)").async(fdMap: [
            write[0]: write[1],
            write[1]: write[0],
        ])
        pipes.forEach { $0.fileHandleForWriting.close() }
        let output = pipes.map {
            String(data: $0.fileHandleForReading.handle.readDataToEndOfFile(), encoding: .utf8)
        }
        try res.succeed()
        XCTAssertEqual(output, ["stuff-to-b", "stuff-to-a"])

        try cmd("rm", cProgramFile).run()
        try cmd("rm", cProgramExecutable).run()
    }

    func testCdSuccess() throws {
        let originalWD = try cmd("pwd").runString()
        let tmpDir = FileManager.default.temporaryDirectory.path
        let newWD = try FileManager.default.withCurrentDirectoryPath(tmpDir) {
            try cmd("pwd").runString()
        }
        let finalWD = try cmd("pwd").runString()
        XCTAssertNotEqual(originalWD, newWD)
        XCTAssertEqual(originalWD, finalWD)
    }

    func testCdFailure() throws {
        let body = { XCTFail("body should not be run") }
        XCTAssertThrowsError(try FileManager.default.withCurrentDirectoryPath("shouldnt-exist", body: body)) { error in
            XCTAssertEqual("\(error)", "ChangeDirectoryFailedError()")
        }
    }

    func testCdRethrows() throws {
        let tmpDir = FileManager.default.temporaryDirectory.path
        struct Foo: Error {}
        XCTAssertThrowsError(try FileManager.default.withCurrentDirectoryPath(tmpDir) { throw Foo() }) { error in
            XCTAssertEqual("\(error)", "Foo()")
        }
    }
}
