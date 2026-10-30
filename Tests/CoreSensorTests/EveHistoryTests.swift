//
//  EveHistoryTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import CoreSensor

final class EveHistoryTests: XCTestCase {

    /// 2001-01-01 + 1000 intervals
    let start = Date(timeIntervalSinceReferenceDate: 600_000)

    func testEmpty() {
        let history = EveHistory()
        XCTAssertEqual(history.lastIndex, 0)
        XCTAssertNil(history.entries(from: 0))
        XCTAssertEqual(history.status.hexString, "00000000" + "00000000" + "00000000" + "0201020202" + "0000" + "C00F" + "00000000" + "000000000101")
    }

    func testAverage() {
        var history = EveHistory()
        let samples = (0 ..< 25).map {
            EveHistory.Sample(date: start + TimeInterval($0 * 60), temperature: Float($0), humidity: 50)
        }
        // third bucket ends after now
        let count = history.append(averaging: samples, now: start + 1200)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(history.entries.map(\.index), [2, 3])
        XCTAssertEqual(history.entries.map(\.date), [start + 600, start + 1200])
        XCTAssertEqual(history.entries.map(\.temperature), [4.5, 14.5])
        XCTAssertEqual(history.referenceDate, start + 600)
        // already stored buckets are skipped
        XCTAssertEqual(history.append(averaging: samples, now: start + 1800), 1)
        XCTAssertEqual(history.entries.map(\.temperature), [4.5, 14.5, 22])
    }

    func testEncoding() {
        var history = EveHistory()
        history.append(date: start, temperature: 20.92, humidity: 44.68)
        history.append(date: start + 600, temperature: -1.5, humidity: 101)
        // reference time 600000 = 0x000927C0
        XCTAssertEqual(history.status.hexString, "58020000" + "00000000" + "C0270900" + "0201020202" + "0400" + "C00F" + "00000000" + "000000000101")
        guard let (data, next) = history.entries(from: 0) else {
            XCTFail()
            return
        }
        XCTAssertEqual(next, 4)
        XCTAssertEqual(data.hexString,
            "15" + "01000000" + "01000000" + "81" + "C0270900" + "00000000000000" +
            "0E" + "02000000" + "00000000" + "03" + "2C08" + "7411" +
            "0E" + "03000000" + "58020000" + "03" + "6AFF" + "1027"
        )
        XCTAssertNil(history.entries(from: next))
        // resume from an entry Eve already has
        XCTAssertEqual(history.entries(from: 3)?.data.count, 14)
    }

    func testTemperatureEncoding() {
        var history = EveHistory(fields: .temperature)
        history.append(date: start, temperature: 20.92, humidity: 0)
        history.append(date: start + 600, temperature: -1.5, humidity: 0)
        XCTAssertEqual(history.status.hexString, "58020000" + "00000000" + "C0270900" + "010102" + "0400" + "C00F" + "00000000" + "000000000101")
        guard let (data, next) = history.entries(from: 0) else {
            XCTFail()
            return
        }
        XCTAssertEqual(next, 4)
        XCTAssertEqual(data.hexString,
            "15" + "01000000" + "01000000" + "81" + "C0270900" + "00000000000000" +
            "0C" + "02000000" + "00000000" + "01" + "2C08" +
            "0C" + "03000000" + "58020000" + "01" + "6AFF"
        )
        XCTAssertEqual(history.entries(from: 3)?.data.count, 12)
    }

    func testRequestedIndex() {
        XCTAssertEqual(EveHistory.requestedIndex(Data([0x01, 0x14, 0x01, 0x00, 0x00, 0x00, 0x00])), 1)
        XCTAssertEqual(EveHistory.requestedIndex(Data([0x01, 0x14, 0x2A, 0x01, 0x00, 0x00, 0x00])), 0x012A)
        XCTAssertNil(EveHistory.requestedIndex(Data([0x01, 0x14])))
    }

    func testBatches() {
        var history = EveHistory()
        for i in 0 ..< 30 {
            history.append(date: start + TimeInterval(i) * 600, temperature: 20, humidity: 50)
        }
        var index: UInt32 = 0
        var reads = 0
        var bytes = 0
        while let (data, next) = history.entries(from: index) {
            index = next
            reads += 1
            bytes += data.count
        }
        XCTAssertEqual(reads, 3) // 31 entries, 11 per read
        XCTAssertEqual(bytes, 21 + 30 * 14)
    }

    func testMemoryWrap() {
        var history = EveHistory()
        let total = Int(EveHistory.memorySize) + 9
        for i in 0 ..< total {
            history.append(date: start + TimeInterval(i) * 600, temperature: 20, humidity: 50)
        }
        let lastIndex = UInt32(total + 1)
        XCTAssertEqual(history.lastIndex, lastIndex)
        XCTAssertEqual(history.entries.count, Int(EveHistory.memorySize) - 1)
        let status = [UInt8](history.status)
        XCTAssertEqual(UInt16(status[17]) | UInt16(status[18]) << 8, EveHistory.memorySize)
        let firstIndex = lastIndex - UInt32(EveHistory.memorySize) + 1
        XCTAssertEqual(UInt32(status[21]) | UInt32(status[22]) << 8, firstIndex)
        // requests for overwritten entries start at the oldest slot, sent as the reference entry
        guard let (data, _) = history.entries(from: 1) else {
            XCTFail()
            return
        }
        XCTAssertEqual(data.first, 0x15)
        XCTAssertEqual(UInt32(data[1]) | UInt32(data[2]) << 8, firstIndex)
        XCTAssertEqual(data[21], 0x0E)
    }
}

private extension Data {

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
