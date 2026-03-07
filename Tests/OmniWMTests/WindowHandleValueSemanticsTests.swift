import Foundation
import XCTest
@testable import OmniWM

final class WindowHandleValueSemanticsTests: XCTestCase {
    func testEqualWhenIdAndPidMatch() {
        let id = UUID()
        let lhs = WindowHandle(id: id, pid: 42)
        let rhs = WindowHandle(id: id, pid: 42)
        XCTAssertEqual(lhs, rhs)
    }

    func testHashingSupportsDictionaryByValue() {
        let id = UUID()
        let lhs = WindowHandle(id: id, pid: 777)
        let rhs = WindowHandle(id: id, pid: 777)

        var dict: [WindowHandle: Int] = [:]
        dict[lhs] = 1
        dict[rhs] = 2

        XCTAssertEqual(dict.count, 1)
        XCTAssertEqual(dict[lhs], 2)
    }
}
