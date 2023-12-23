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
            try! pipe.fileHandleForWriting.handle.write(contentsOf: string.data(using: .utf8)!)
            // TODO: Need to synchronize()? Fails with error 512 on macOS if we do...
            //try! pipe.fileHandleForWriting.handle.synchronize()
            waiter.leave()
        }
        writeThread.start()
        
        try XCTAssertEqual(pipe.fileHandleForReading.handle.read(upToCount: string.count), string.data(using: .utf8)!)
        waiter.wait()
    }
}
