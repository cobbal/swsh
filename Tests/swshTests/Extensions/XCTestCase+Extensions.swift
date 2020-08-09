import XCTest

extension XCTestCase {
    #if false // https://bugs.swift.org/browse/SR-11501
    public func unwrap<T>(
        _ expression: @autoclosure () throws -> T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T {
        try XCTUnwrap(expression(), message(), file: file, line: line)
    }

    #else
    struct NilError: Error {}

    public func unwrap<T>(
        _ expression: @autoclosure () throws -> T?,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T {
        guard let e = try expression() else {
            XCTFail(message(), file: (file), line: line)
            throw NilError()
        }
        return e
    }
    #endif
}
