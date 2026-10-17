import Foundation

public enum DeviceReorder {
    /// `Array.move(fromOffsets:toOffset:)` index when dropping the item at
    /// `from` onto the item currently at `to`.
    public static func destination(from: Int, droppingOn to: Int) -> Int? {
        guard from != to, from >= 0, to >= 0 else { return nil }
        return from < to ? to + 1 : to
    }

    public static func destination(draggingUID: String, ontoUID: String, in uids: [String]) -> Int? {
        guard let from = uids.firstIndex(of: draggingUID),
              let to = uids.firstIndex(of: ontoUID) else { return nil }
        return destination(from: from, droppingOn: to)
    }

    public static func move(draggingUID: String, ontoUID: String, in uids: [String]) -> (from: IndexSet, to: Int)? {
        guard let from = uids.firstIndex(of: draggingUID),
              let destination = destination(draggingUID: draggingUID, ontoUID: ontoUID, in: uids) else { return nil }
        return (IndexSet(integer: from), destination)
    }

    /// One step up the list. `Array.move(fromOffsets:toOffset:)` counts the
    /// destination in the pre-move array, so moving down needs `index + 2`.
    public static func moveUp(index: Int, count: Int) -> (from: IndexSet, to: Int)? {
        guard index > 0, index < count else { return nil }
        return (IndexSet(integer: index), index - 1)
    }

    public static func moveDown(index: Int, count: Int) -> (from: IndexSet, to: Int)? {
        guard index >= 0, index < count - 1 else { return nil }
        return (IndexSet(integer: index), index + 2)
    }
}
