import Foundation

enum DeviceReorder {
    /// `Array.move(fromOffsets:toOffset:)` index when dropping the item at
    /// `from` onto the item currently at `to`.
    static func destination(from: Int, droppingOn to: Int) -> Int? {
        guard from != to, from >= 0, to >= 0 else { return nil }
        return from < to ? to + 1 : to
    }

    static func destination(draggingUID: String, ontoUID: String, in uids: [String]) -> Int? {
        guard let from = uids.firstIndex(of: draggingUID),
              let to = uids.firstIndex(of: ontoUID) else { return nil }
        return destination(from: from, droppingOn: to)
    }

    static func move(draggingUID: String, ontoUID: String, in uids: [String]) -> (from: IndexSet, to: Int)? {
        guard let from = uids.firstIndex(of: draggingUID),
              let destination = destination(draggingUID: draggingUID, ontoUID: ontoUID, in: uids) else { return nil }
        return (IndexSet(integer: from), destination)
    }
}
