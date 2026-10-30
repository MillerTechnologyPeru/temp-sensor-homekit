//
//  SensorStoreTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
import CoreModel
@testable import CoreSensor

final class SensorStoreTests: XCTestCase {

    /// 2001-01-01 + 1000 intervals
    let start = Date(timeIntervalSinceReferenceDate: 600_000)

    let a = Sensor.ID(type: "com.Govee.Thermometer", serialNumber: "GVH5072_7A27")

    let b = Sensor.ID(type: "com.TPMS.Sensor", serialNumber: "AA:BB:CC:DD:EE:FF")

    func makeStore(limit: UInt = SensorStore.defaultLimit) throws -> SensorStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("SensorStoreTests-\(UUID()).sqlite")
            .path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return try SensorStore(path: path, limit: limit)
    }

    func sensor(_ id: Sensor.ID) -> Sensor {
        Sensor(
            id: id,
            type: String(id.rawValue.split(separator: "/")[0]),
            peripheral: UUID().uuidString,
            name: "Sensor",
            manufacturer: "Manufacturer",
            model: "Model",
            serialNumber: String(id.rawValue.split(separator: "/")[1]),
            lastSeen: start
        )
    }

    /// Creates the sensors, as the scanner does before saving history.
    func makeStore(limit: UInt = SensorStore.defaultLimit, sensors: [Sensor.ID]) async throws -> SensorStore {
        let store = try makeStore(limit: limit)
        for id in sensors {
            try await store.update(sensor(id))
        }
        return store
    }

    func samples(_ count: Int, from date: Date) -> [EveHistory.Sample] {
        (0 ..< count).map {
            EveHistory.Sample(date: date + TimeInterval($0) * EveHistory.interval, temperature: Float($0) / 4, humidity: 50 + Float($0 % 10))
        }
    }

    func testSensor() async throws {
        let store = try makeStore()
        let sensors = try await store.sensors()
        XCTAssertEqual(sensors, [])
        var value = sensor(a)
        value.temperature = 21.5
        value.humidity = 40
        value.batteryLevel = 87
        value.lowBattery = false
        try await store.update(value)
        let stored = try await store.sensor(for: a)
        XCTAssertEqual(stored, value)
        XCTAssertEqual(stored?.reading, ReadingBuffer.Reading(date: start, temperature: 21.5, humidity: 40))
        // firmware is kept after reopening the file
        value.firmwareRevision = "1.03.01"
        try await store.update(value)
        let reopened = try SensorStore(path: store.path)
        let reread = try await reopened.sensors()
        XCTAssertEqual(reread, [value])
        XCTAssertEqual(reread.first?.firmwareRevision, "1.03.01")
        XCTAssertNil(reread.first?.pressure)
        XCTAssertNil(reread.first?.batteryVoltage)
    }

    func testChanges() async throws {
        let store = try makeStore()
        var history = EveHistory()
        history.append(averaging: samples(3, from: start), now: .distantFuture)
        let value = sensor(a)
        try await store.update(value)
        try await store.saveHistory(history, replacing: EveHistory(), for: a)
        var updated = value
        updated.historyReferenceDate = history.referenceDate
        var changes = store.changes.makeAsyncIterator()
        let first = await changes.next()
        let second = await changes.next()
        let third = await changes.next()
        XCTAssertEqual(first, .sensor(value))
        XCTAssertEqual(second, .sensor(updated))
        XCTAssertEqual(third, .history(a, history))
    }

    func testEmptyHistory() async throws {
        let store = try await makeStore(sensors: [a])
        let history = try await store.history(for: a)
        XCTAssertEqual(history, EveHistory())
        // nothing to save without entries
        try await store.saveHistory(EveHistory(), replacing: EveHistory(), for: a)
        let saved = try await store.history(for: a)
        XCTAssertEqual(saved, EveHistory())
        // unknown sensor
        let unknown = try await store.history(for: b, fields: .temperature)
        XCTAssertEqual(unknown, EveHistory(fields: .temperature))
    }

    func testSaveAndRead() async throws {
        let store = try await makeStore(sensors: [a, b])
        var historyA = EveHistory()
        historyA.append(averaging: samples(10, from: start), now: .distantFuture)
        var historyB = EveHistory(fields: .temperature)
        historyB.append(averaging: samples(3, from: start + 3600), now: .distantFuture)
        try await store.saveHistory(historyA, replacing: EveHistory(), for: a)
        try await store.saveHistory(historyB, replacing: EveHistory(fields: .temperature), for: b)
        let readA = try await store.history(for: a)
        let readB = try await store.history(for: b, fields: .temperature)
        XCTAssertEqual(readA, historyA)
        XCTAssertEqual(readB, historyB)
        XCTAssertEqual(readA.status, historyA.status)
        let sensorA = try await store.sensor(for: a)
        XCTAssertEqual(sensorA?.historyReferenceDate, historyA.referenceDate)
        // reopening the file reads the same history
        let reopened = try SensorStore(path: store.path)
        let reread = try await reopened.history(for: a)
        XCTAssertEqual(reread, historyA)
    }

    func testSaveChanges() async throws {
        let store = try await makeStore(sensors: [a])
        var history = EveHistory()
        history.append(averaging: samples(10, from: start), now: .distantFuture)
        try await store.saveHistory(history, replacing: EveHistory(), for: a)
        let oldValue = history
        history.append(averaging: samples(10, from: start + 10 * EveHistory.interval), now: .distantFuture)
        try await store.saveHistory(history, replacing: oldValue, for: a)
        let read = try await store.history(for: a)
        XCTAssertEqual(read, history)
        XCTAssertEqual(read.entries.count, 20)
    }

    func testSaveWrapped() async throws {
        let store = try await makeStore(sensors: [a])
        let capacity = Int(EveHistory.memorySize) - 1
        var history = EveHistory()
        history.append(averaging: samples(capacity, from: start), now: .distantFuture)
        try await store.saveHistory(history, replacing: EveHistory(), for: a)
        let oldValue = history
        // the oldest entries are dropped once memory is full
        history.append(averaging: samples(100, from: start + TimeInterval(capacity) * EveHistory.interval), now: .distantFuture)
        XCTAssertEqual(history.entries.count, capacity)
        try await store.saveHistory(history, replacing: oldValue, for: a)
        let read = try await store.history(for: a)
        XCTAssertEqual(read, history)
        // entries dropped from the Eve history memory stay in the database
        let count = try await store.historyCount(for: a)
        XCTAssertEqual(count, UInt(capacity + 100))
    }

    func testLimit() async throws {
        let store = try await makeStore(limit: 10, sensors: [a, b])
        var historyA = EveHistory()
        historyA.append(averaging: samples(25, from: start), now: .distantFuture)
        var historyB = EveHistory()
        historyB.append(averaging: samples(5, from: start), now: .distantFuture)
        try await store.saveHistory(historyA, replacing: EveHistory(), for: a)
        try await store.saveHistory(historyB, replacing: EveHistory(), for: b)
        // the oldest entries over the limit are deleted, for each sensor
        let entries = try await store.database.fetch(SensorHistoryEntry.self)
        XCTAssertEqual(entries.filter { $0.sensor == a.rawValue }.map(\.index).sorted(), Array(17 ... 26))
        XCTAssertEqual(entries.filter { $0.sensor == b.rawValue }.count, 5)
        let oldValue = historyA
        historyA.append(averaging: samples(3, from: start + 25 * EveHistory.interval), now: .distantFuture)
        try await store.saveHistory(historyA, replacing: oldValue, for: a)
        let updated = try await store.database.fetch(SensorHistoryEntry.self, predicate: SensorHistoryEntry.CodingKeys.sensor == a.rawValue)
        XCTAssertEqual(updated.map(\.index).sorted(), Array(20 ... 29))
    }

    func testMissingEntry() async throws {
        let store = try await makeStore(sensors: [a])
        var history = EveHistory()
        history.append(averaging: samples(10, from: start), now: .distantFuture)
        XCTAssertEqual(history.entries.map(\.index), Array(2 ... 11))
        // save entries 2-6, then 8-11 as if 7 had been saved
        let first = EveHistory(referenceDate: history.referenceDate!, entries: Array(history.entries.prefix(5)))
        let missing = EveHistory(referenceDate: history.referenceDate!, entries: Array(history.entries.prefix(6)))
        try await store.saveHistory(first, replacing: EveHistory(), for: a)
        try await store.saveHistory(history, replacing: missing, for: a)
        // the history is deleted, so it is downloaded or recorded again
        let read = try await store.history(for: a)
        XCTAssertEqual(read, EveHistory())
        let sensor = try await store.sensor(for: a)
        XCTAssertNil(sensor?.historyReferenceDate)
        let count = try await store.historyCount(for: a)
        XCTAssertEqual(count, 0)
        try await store.saveHistory(history, replacing: EveHistory(), for: a)
        let saved = try await store.history(for: a)
        XCTAssertEqual(saved, history)
    }
}
