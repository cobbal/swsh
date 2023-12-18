import Foundation
@testable import swsh
import XCTest

class FDPipeTests: XCTestCase {
    func testPipePipiness() throws {
        let string = "SomeString"
        let pipe = FDPipe()

        let waiter = DispatchGroup()
        waiter.enter()
        let writeThread = Thread {
            try! pipe.fileHandleForWriting.write(contentsOf: string.data(using: .utf8)!)
            try! pipe.fileHandleForWriting.synchronize()
            waiter.leave()
        }
        writeThread.start()
        
        try XCTAssertEqual(pipe.fileHandleForReading.read(upToCount: string.count), string.data(using: .utf8)!)
        waiter.wait()
    }
}
