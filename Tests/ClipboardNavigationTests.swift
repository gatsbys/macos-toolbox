import Foundation
import Testing
@testable import ToolboxCore

@Test func historyArrowsMoveToNextAndPreviousItems() {
    let ids = [UUID(), UUID(), UUID()]
    #expect(ClipboardHistoryNavigation.move(from: ids[0], in: ids, by: 1) == ids[1])
    #expect(ClipboardHistoryNavigation.move(from: ids[1], in: ids, by: -1) == ids[0])
}

@Test func historyArrowsStayWithinListBounds() {
    let ids = [UUID(), UUID(), UUID()]
    #expect(ClipboardHistoryNavigation.move(from: ids[0], in: ids, by: -1) == ids[0])
    #expect(ClipboardHistoryNavigation.move(from: ids[2], in: ids, by: 1) == ids[2])
}

@Test func historyArrowsUseFilteredItemsAndDefaultSelection() {
    let ids = [UUID(), UUID(), UUID()]
    #expect(ClipboardHistoryNavigation.move(from: nil, in: ids, by: 1) == ids[1])
    #expect(ClipboardHistoryNavigation.move(from: UUID(), in: ids, by: -1) == ids[0])
    #expect(ClipboardHistoryNavigation.move(from: ids[0], in: [ids[0], ids[2]], by: 1) == ids[2])
}

@Test func historyArrowsHandleEmptyAndSingleResult() {
    let id = UUID()
    #expect(ClipboardHistoryNavigation.move(from: id, in: [], by: 1) == nil)
    #expect(ClipboardHistoryNavigation.move(from: id, in: [id], by: 1) == id)
    #expect(ClipboardHistoryNavigation.move(from: id, in: [id], by: -1) == id)
}
