//
//  ReadingBufferTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import CoreSensor

final class ReadingBufferTests: XCTestCase {

    /// 2001-01-01 + 1000 intervals
    let start = Date(timeIntervalSinceReferenceDate: 600_000)

    func reading(_ seconds: TimeInterval, _ temperature: Float, _ humidity: Float? = 50) -> ReadingBuffer.Reading {
        ReadingBuffer.Reading(date: start + seconds, temperature: temperature, humidity: humidity)
    }

    func testDuplicates() {
        var buffer = ReadingBuffer(start: start)
        XCTAssertTrue(buffer.append(reading(0, 20)))
        XCTAssertFalse(buffer.append(reading(1, 20)))
        XCTAssertTrue(buffer.append(reading(2, 20, 51)))
        XCTAssertFalse(buffer.append(reading(3, 20, 51)))
        XCTAssertTrue(buffer.append(reading(4, 21, 51)))
        // older readings are ignored
        XCTAssertFalse(buffer.append(reading(3, 22)))
        XCTAssertEqual(buffer.readings.map(\.date), [start, start + 2, start + 4])
        // a reading equal to the previous one is skipped
        var restored = ReadingBuffer(start: start, previous: reading(-60, 20))
        XCTAssertFalse(restored.append(reading(0, 20)))
        XCTAssertTrue(restored.readings.isEmpty)
    }

    func testCapacity() {
        var buffer = ReadingBuffer(capacity: 10, start: start)
        XCTAssertEqual(buffer.capacity, 10)
        for i in 0 ..< 1000 {
            buffer.append(reading(TimeInterval(i), Float(i)))
        }
        // the oldest readings are dropped, so the storage reserved up front never grows
        XCTAssertEqual(buffer.readings.count, 10)
        XCTAssertEqual(buffer.readings.first?.temperature, 990)
        XCTAssertEqual(buffer.previous?.temperature, 989)
        XCTAssertEqual(ReadingBuffer(start: start).capacity, ReadingBuffer.defaultCapacity)
    }

    func testWeightedAverage() {
        var buffer = ReadingBuffer(start: start)
        // 20° for 9 minutes, 30° for 1 minute
        buffer.append(reading(0, 20, 40))
        buffer.append(reading(540, 30, 50))
        // the interval isn't complete yet
        XCTAssertEqual(buffer.averages(through: start + 599), [])
        let samples = buffer.averages(through: start + 600)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.date, start + 600)
        XCTAssertEqual(samples.first?.temperature ?? 0, 21, accuracy: 0.001)
        XCTAssertEqual(samples.first?.humidity ?? 0, 41, accuracy: 0.001)
        // averaged readings are removed, keeping the last value
        XCTAssertTrue(buffer.readings.isEmpty)
        XCTAssertEqual(buffer.previous, reading(540, 30, 50))
        XCTAssertEqual(buffer.nextInterval, start + 600)
    }

    func testRepeatsLastValue() {
        var buffer = ReadingBuffer(start: start)
        buffer.append(reading(0, 20))
        buffer.append(reading(300, 22))
        // two more intervals without new readings
        let samples = buffer.averages(through: start + 1800)
        XCTAssertEqual(samples.map(\.date), [start + 600, start + 1200, start + 1800])
        XCTAssertEqual(samples.map(\.temperature), [21, 22, 22])
        // nothing again until the next interval ends
        XCTAssertEqual(buffer.averages(through: start + 2000), [])
    }

    func testReadingsAcrossIntervals() {
        var buffer = ReadingBuffer(start: start)
        buffer.append(reading(0, 20))
        buffer.append(reading(900, 30))
        buffer.append(reading(1300, 10))
        // averaging one interval at a time keeps the readings for the next one
        let first = buffer.averages(through: start + 600)
        XCTAssertEqual(first.map(\.temperature), [20])
        XCTAssertEqual(buffer.readings.count, 2)
        // 30° for 100 seconds, then 10° for 500 seconds
        let second = buffer.averages(through: start + 1800)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second.first?.temperature, 25)
        XCTAssertEqual(second.last?.temperature ?? 0, 40 / 3, accuracy: 0.001)
    }

    func testStoredValue() {
        // after a restart, the last stored value is used until the sensor is scanned
        let startup = start + 300
        var buffer = ReadingBuffer(start: startup, previous: reading(-3600, 18))
        XCTAssertEqual(buffer.nextInterval, start)
        let samples = buffer.averages(through: start + 1200)
        XCTAssertEqual(samples.map(\.date), [start + 600, start + 1200])
        XCTAssertEqual(samples.map(\.temperature), [18, 18])
        // scanned partway through the next interval
        buffer.append(reading(1500, 24))
        let scanned = buffer.averages(through: start + 1800)
        XCTAssertEqual(scanned.map(\.temperature), [21])
    }

    func testNewSensor() {
        // no stored value, so intervals before the first reading are skipped
        var buffer = ReadingBuffer(start: start)
        XCTAssertEqual(buffer.averages(through: start + 1800), [])
        XCTAssertEqual(buffer.nextInterval, start + 1800)
        // the first reading counts from when it arrived
        buffer.append(reading(2100, 20))
        let samples = buffer.averages(through: start + 2400)
        XCTAssertEqual(samples.map(\.date), [start + 2400])
        XCTAssertEqual(samples.map(\.temperature), [20])
    }

    func testTemperatureOnly() {
        var buffer = ReadingBuffer(start: start)
        buffer.append(reading(0, 20, nil))
        let samples = buffer.averages(through: start + 600)
        XCTAssertEqual(samples.map(\.temperature), [20])
        XCTAssertEqual(samples.map(\.humidity), [0])
    }

    func testDay() {
        var buffer = ReadingBuffer(start: start)
        var history = EveHistory()
        // one reading per second for a day, changing every minute
        for second in 0 ..< 24 * 60 * 60 {
            buffer.append(reading(TimeInterval(second), Float(second / 60 % 10), 50))
            // flushed after each scan, about every 45 seconds
            if second % 45 == 0 {
                for sample in buffer.averages(through: start + TimeInterval(second)) {
                    history.append(date: sample.date, temperature: sample.temperature, humidity: sample.humidity)
                }
            }
        }
        XCTAssertLessThanOrEqual(buffer.readings.count, ReadingBuffer.defaultCapacity)
        XCTAssertEqual(history.entries.count, 143)
        XCTAssertEqual(history.entries.map(\.index), Array(2 ... 144))
        // each 10 minutes covers values 0 to 9 equally
        XCTAssertTrue(history.entries.allSatisfy { abs($0.temperature - 4.5) < 0.001 })
    }
}
