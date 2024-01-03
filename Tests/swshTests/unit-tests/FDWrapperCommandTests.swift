@testable import swsh
import XCTest

final class FDWrapperCommandTests: XCTestCase {
    let inner = MockCommand(description: "inner")
    lazy var cmd = FDWrapperCommand(inner: inner, opening: "/dev/null", toHandle: 0, oflag: O_RDONLY)
    lazy var invalidCmd = FDWrapperCommand( inner: inner, opening: "\(UUID())", toHandle: 0, oflag: O_RDONLY)

    func result() throws -> (outer: FDWrapperCommand.Result, inner: MockCommand.Result) {
        let result = try unwrap(cmd.coreAsync(fdMap: [5: 3]) as? FDWrapperCommand.Result)
        // let result = try unwrap(cmd.coreAsync(fdMap: [5: 3]) as? FDWrapperCommand.Result)
        let innerResult = try unwrap(result.innerResult as? MockCommand.Result)
        return (outer: result, inner: innerResult)
    }

    func testConstructor() {
        XCTAssertEqual(cmd.inner as? MockCommand, inner)
    }

    func testValidCoreAsync() throws {
        let map = try result().inner.fdMap
        XCTAssertEqual(map.count, 2)
        XCTAssertNotNil(map[0])
        XCTAssertEqual(map[5], 3)
    }

    func testInvalidCoreAsync() throws {
        let result = try unwrap(invalidCmd.coreAsync(fdMap: [:]) as? SyscallError)
        XCTAssert(result.command === invalidCmd)
        XCTAssertEqual(result.errno, ENOENT)
    }

    func testResultSucceeds() throws {
        let (outer, inner) = try result()
        XCTAssertTrue(outer.isRunning)
        inner.setExit(code: 0)
        XCTAssertFalse(outer.isRunning)
        XCTAssertNoThrow(try outer.succeed())
    }

    func testResultFailed() throws {
        let (outer, inner) = try result()
        XCTAssertTrue(outer.isRunning)
        inner.setExit(code: 42)
        XCTAssertFalse(outer.isRunning)
        XCTAssertEqual(outer.exitCode(), 42)
        XCTAssertThrowsError(try outer.succeed())
    }
}

final class FDWrapperCommandExtensionsTests: XCTestCase {
    let inner = MockCommand(description: "inner")
    var outerResult: FDWrapperCommand.Result!
    var innerResult: MockCommand.Result!
    var error: Error!
    var syscallError: SyscallError! { error as? SyscallError }

    var handle: FileHandle? {
        let fd: FileDescriptor = innerResult?.fdMap[.stdin] != .stdin ? .stdin : .stdout
        return (innerResult?.fdMap[fd]).map { FileHandle(fileDescriptor: $0.rawValue) }
    }

    // note: fresh between tests
    let tmpUrl = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString, isDirectory: false)
    lazy var tmpPath = tmpUrl.path

    override func setUp() {
        super.setUp()
        try! "Hello".write(to: tmpUrl, atomically: false, encoding: .utf8)
    }

    func succeed(_ cmd: Command) throws {
        outerResult = try unwrap(cmd.async() as? FDWrapperCommand.Result)
        innerResult = try unwrap(outerResult.innerResult as? MockCommand.Result)
    }

    func failure(_ cmd: @autoclosure () throws -> Command, file: StaticString = #file, line: UInt = #line) {
        do {
            let result = try cmd()
            error = try unwrap(result.async() as? Error, file: file, line: line)
        } catch let e {
            error = e
        }
    }

    func deleteTmp() {
        try? FileManager.default.removeItem(at: tmpUrl)
    }

    #if swift(<5.1)
    func close() {
        handle?.closeFile()
    }
    #else
    func close() {
        if #available(macOS 10.15, *) {
            try? handle?.close()
        } else {
            handle?.closeFile()
        }
    }
    #endif

    // MARK: - Output redirection

    func testOutputCreatingFileSuccess() throws {
        deleteTmp()
        try succeed(inner.output(creatingFile: tmpPath))
        handle?.write("Hello".data(using: .utf8)!)
        close()
        innerResult.setExit(code: 0)
        try outerResult.succeed()

        XCTAssertEqual(try String(contentsOf: tmpUrl), "Hello")
    }

    func testOutputCreatingFileFailure() throws {
        failure(inner.output(creatingFile: tmpPath))
        XCTAssertEqual(syscallError.errno, EEXIST)
    }

    func testOutputOverwritingFile() throws {
        try succeed(inner.output(overwritingFile: tmpPath))
        handle?.write("Hiya".data(using: .utf8)!)
        close()
        innerResult.setExit(code: 0)
        try outerResult.succeed()

        XCTAssertEqual(try String(contentsOf: tmpUrl), "Hiya")
    }

    func testOutputAppendingNoCreateSuccess() throws {
        // TODO: On Windows, it appears that the O_APPEND flag is being ignored. No idea why...
        try succeed(inner.append(toFile: tmpPath, createFile: false))
        handle?.write("Hiya".data(using: .utf8)!)
        close()

        XCTAssertEqual(try String(contentsOf: tmpUrl), "HelloHiya")
    }

    func testOutputAppendingNoCreateFail() throws {
        deleteTmp()
        failure(inner.append(toFile: tmpPath, createFile: false))
        XCTAssertEqual(syscallError.errno, ENOENT)
    }

    func testOutputAppendingCreate() throws {
        deleteTmp()
        try succeed(inner.append(toFile: tmpPath))
    }

    func testDuplicateFd() throws {
        let pipe = FDPipe()
        try succeed(inner.duplicateFd(source: pipe.fileHandleForReading.fileDescriptor, destination: 35))
        XCTAssertEqual(innerResult.fdMap[35], pipe.fileHandleForReading.fileDescriptor)
    }

    func testCombineError() throws {
        try succeed(inner.combineError)
        XCTAssertEqual(innerResult.fdMap[2], 1)
    }

    // MARK: - Input

    func handleString() throws -> String {
        String(data: try unwrap(handle).readDataToEndOfFile(), encoding: .utf8)!
    }

    func testInputStringSuccess() throws {
        try succeed(inner.input("xyz"))
        XCTAssertEqual(try handleString(), "xyz")
    }

    func testInputStringFailure() {
        failure(try inner.input("ü", encoding: .ascii))
        XCTAssert(error is StringEncodingError)
    }

    func testInputJSON() throws {
        try succeed(inner.input(withJSONObject: ["foo": "bar"]))
        XCTAssertEqual(try handleString(), "{\"foo\":\"bar\"}")
    }

    func testInputEncodable() throws {
        try succeed(inner.inputJSON(from: ["foo": "bar"]))
        XCTAssertEqual(try handleString(), "{\"foo\":\"bar\"}")
    }

    func testInputFromFile() throws {
        try succeed(inner.input(fromFile: tmpPath))
        XCTAssertEqual(try handleString(), "Hello")
    }

    func testDescription() throws {
        XCTAssertEqual("\(inner.combineError)", "inner")
    }
}
