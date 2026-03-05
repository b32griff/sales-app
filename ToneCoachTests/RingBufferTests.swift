import XCTest
@testable import ToneCoach

final class RingBufferTests: XCTestCase {

    func testAppendAndRead() {
        var buf = RingBuffer<Int>(capacity: 5, defaultValue: 0)
        buf.append(1)
        buf.append(2)
        buf.append(3)
        XCTAssertEqual(buf.count, 3)
        XCTAssertEqual(buf.toArray(), [1, 2, 3])
    }

    func testWrapAround() {
        var buf = RingBuffer<Int>(capacity: 3, defaultValue: 0)
        buf.append(1)
        buf.append(2)
        buf.append(3)
        buf.append(4) // overwrites 1
        XCTAssertEqual(buf.count, 3)
        XCTAssertEqual(buf.toArray(), [2, 3, 4])
    }

    func testLastValue() {
        var buf = RingBuffer<Int>(capacity: 3, defaultValue: 0)
        XCTAssertNil(buf.last)
        buf.append(10)
        XCTAssertEqual(buf.last, 10)
        buf.append(20)
        XCTAssertEqual(buf.last, 20)
    }

    func testRemoveAll() {
        var buf = RingBuffer<Int>(capacity: 5, defaultValue: 0)
        buf.append(contentsOf: [1, 2, 3])
        buf.removeAll()
        XCTAssertEqual(buf.count, 0)
        XCTAssertEqual(buf.toArray(), [])
        XCTAssertNil(buf.last)
    }

    func testAppendContentsOf() {
        var buf = RingBuffer<Double>(capacity: 4, defaultValue: 0)
        buf.append(contentsOf: [1.0, 2.0, 3.0, 4.0, 5.0])
        XCTAssertEqual(buf.count, 4)
        XCTAssertEqual(buf.toArray(), [2.0, 3.0, 4.0, 5.0])
    }

    func testCapacityNeverExceeded() {
        var buf = RingBuffer<Int>(capacity: 3, defaultValue: 0)
        for i in 0..<100 {
            buf.append(i)
        }
        XCTAssertEqual(buf.count, 3)
        XCTAssertEqual(buf.toArray(), [97, 98, 99])
    }

    func testEmptyBuffer() {
        let buf = RingBuffer<Int>(capacity: 10, defaultValue: 0)
        XCTAssertEqual(buf.count, 0)
        XCTAssertEqual(buf.toArray(), [])
        XCTAssertNil(buf.last)
    }

    func testSingleCapacity() {
        var buf = RingBuffer<Int>(capacity: 1, defaultValue: 0)
        buf.append(42)
        XCTAssertEqual(buf.toArray(), [42])
        buf.append(99)
        XCTAssertEqual(buf.toArray(), [99])
        XCTAssertEqual(buf.count, 1)
    }
}
