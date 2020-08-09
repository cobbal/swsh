import Foundation

internal enum FDOperation {
    case dup(src: Int32, dst: Int32)
    case close(fd: Int32)
}

extension FDOperation {
    internal struct Remapper {
        typealias Graph = [Int32: [Int32]]

        let graph: Graph
        lazy var cycles = Remapper.detectCycles(graph: graph)
        private var output = [FDOperation]()
        lazy var nontrivialCycles = cycles.filter { $0.count > 1 }
        lazy var problems = Set(nontrivialCycles.flatMap { $0 })
        lazy var unvisited = Set(graph.keys)
        lazy var used = problems

        init(_ map: FDMap) {
            var graph = Graph()
            for (dst, src) in map {
                graph[dst.rawValue] ??= []
                graph[src.rawValue, default: []].append(dst.rawValue)
            }
            self.graph = graph
        }

        static func detectCycles(graph: Graph) -> [[Int32]] {
            // Detect cycles. We can get away with this knock-off DFS because our graph has no nodes with
            // >1 incoming edge
            var unvisited = Set(graph.keys)
            var cycles: [[Int32]] = []
            for root in unvisited.sorted() {
                var stack: [Int32] = []
                func dfs(_ node: Int32) {
                    guard unvisited.contains(node) else { return }
                    unvisited.remove(node)
                    stack.append(node)
                    for dst in graph[node] ?? [] {
                        if dst == root {
                            cycles.append(stack)
                            continue
                        }
                        dfs(dst)
                    }
                }
                dfs(root)
            }
            return cycles
        }

        mutating func dfs(_ node: Int32) {
            guard unvisited.contains(node) else { return }
            unvisited.remove(node)
            for dst in graph[node] ?? [] {
                dfs(dst)
                guard !problems.contains(dst) else { continue }
                output.append(.dup(src: node, dst: dst))
                used.insert(dst)
            }
        }

        mutating func generate() -> [FDOperation] {
            for root in unvisited.sorted() {
                dfs(root)
            }

            // May crash if you try to use >2 billion file handles...
            var tmp: Int32!
            for i: Int32 in 0... {
                if used.contains(i) {
                    continue
                }
                tmp = i
                break
            }
            var closeTmp: Bool = false

            outer: for cycle in nontrivialCycles {
                let nodes = Set(cycle)
                for (i, node) in cycle.enumerated() {
                    guard let dst = graph[node]?.first(where: { !nodes.contains($0) }) else { continue }
                    breakCycle(Array(cycle[(i + 1)...]) + Array(cycle[...i]), endWith: dst)
                    continue outer
                }
                output.append(.dup(src: cycle.last!, dst: tmp))
                breakCycle(cycle, endWith: tmp)
                closeTmp = true
            }

            if closeTmp {
                output.append(.close(fd: tmp))
            }

            return output
        }

        mutating func breakCycle(_ cycle: [Int32], endWith end: Int32) {
            let cycle = cycle.reversed()
            for (src, dst) in zip(cycle.dropFirst(), cycle.dropLast()) {
                output.append(.dup(src: src, dst: dst))
            }
            output.append(.dup(src: end, dst: cycle.last!))
        }
    }
}
