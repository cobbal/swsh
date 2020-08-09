import Foundation
@testable import swsh
import XCTest

class FDOperationTests: XCTestCase {
    func testThings() {
        check(
            source: [1: 2, 2: 1],
            graph: [1: [2], 2: [1]],
            cycles: [[1, 2]]
        )
        check(
            source: [1: 3, 3: 4, 4: 2, 2: 3],
            graph: [1: [], 2: [4], 3: [1, 2], 4: [3]],
            cycles: [[2, 4, 3]]
        )
        check(
            source: [1: 3, 3: 1, 4: 2, 2: 5, 5: 4],
            graph: [1: [3], 2: [4], 3: [1], 4: [5], 5: [2]],
            cycles: [[1, 3], [2, 4, 5]]
        )
        check(
            source: [1: 1, 2: 2, 3: 4, 4: 4],
            graph: [1: [1], 2: [2], 3: [], 4: [3, 4]],
            cycles: [[1], [2], [4]]
        )
        check(
            source: [1: 2, 2: 3, 3: 4],
            graph: [1: [], 2: [1], 3: [2], 4: [3]],
            cycles: []
        )
    }

    func testFDRawRepresentable() {
        XCTAssertEqual(FileDescriptor(rawValue: 42), 42)
    }

    func check(source: FDMap, graph: FDOperation.Remapper.Graph, cycles: [[Int32]]) {
        let genGraph = FDOperation.Remapper(source).graph.mapValues { $0.sorted() }
        XCTAssertEqual(genGraph, graph)
        XCTAssertEqual(FDOperation.Remapper.detectCycles(graph: graph), cycles)
        checkSimulation(map: source)
    }

    func simulate(ops: [FDOperation]) -> [Int32: String] {
        var store: [Int32: String] = [:]
        for op in ops {
            switch op {
            case let .dup(src, dst):
                store[dst] = store[src] ?? "\(src)"
            case let .close(fd):
                store[fd] = "closed"
            }
        }
        return store
    }

    func checkSimulation(map: FDMap) {
        let result = simulate(ops: map.createFdOperations())
        for (dst, src) in map {
            XCTAssertEqual(result[dst.rawValue], "\(src)")
        }
        for (dst, src) in result {
            if let resSrc = map[FileDescriptor(dst)] {
                XCTAssertEqual(src, "\(resSrc)")
            } else {
                XCTAssertEqual(src, "closed")
            }
        }
    }
}
