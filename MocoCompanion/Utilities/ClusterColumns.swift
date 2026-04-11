import Foundation

/// Interval-based cluster-column assignment. Groups transitively
/// overlapping items into clusters and within each cluster assigns
/// every item a `columnIndex` (0-based) and a shared `columnCount`
/// so callers can render them side-by-side without overlap.
enum ClusterColumns {
    struct Assignment {
        let columnIndex: Int
        let columnCount: Int
    }

    /// Inputs are already in the caller's own struct — we ask the
    /// caller to provide start/end minutes for each item and return
    /// assignments in the same order.
    ///
    /// Items are sorted by start ASC, then end DESC before processing,
    /// matching the sort order used in the timeline entry layout.
    static func assign(
        _ items: [(start: Int, end: Int)]
    ) -> [Assignment] {
        let indexed = items.enumerated().map {
            (original: $0.offset, start: $0.element.start, end: $0.element.end)
        }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end > rhs.end
        }

        var resultsByOriginal: [Int: Assignment] = [:]
        var cluster: [(original: Int, start: Int, end: Int)] = []
        var clusterEnd = Int.min

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            var columnEnds: [Int] = []
            var assignments: [Int] = []
            for item in cluster {
                var placed = false
                for (i, end) in columnEnds.enumerated() where item.start >= end {
                    columnEnds[i] = item.end
                    assignments.append(i)
                    placed = true
                    break
                }
                if !placed {
                    assignments.append(columnEnds.count)
                    columnEnds.append(item.end)
                }
            }
            let count = max(columnEnds.count, 1)
            for (i, item) in cluster.enumerated() {
                resultsByOriginal[item.original] = Assignment(
                    columnIndex: assignments[i],
                    columnCount: count
                )
            }
            cluster.removeAll(keepingCapacity: true)
            clusterEnd = Int.min
        }

        for item in sorted {
            if item.start >= clusterEnd {
                flushCluster()
            }
            cluster.append(item)
            clusterEnd = max(clusterEnd, item.end)
        }
        flushCluster()

        return items.indices.map {
            resultsByOriginal[$0] ?? Assignment(columnIndex: 0, columnCount: 1)
        }
    }
}
