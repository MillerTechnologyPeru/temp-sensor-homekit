//
//  EveHistoryStoreTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import CoreSensor

final class EveHistoryStoreTests: XCTestCase {

    /// 2001-01-01 + 1000 intervals
    let start = Date(timeIntervalSinceReferenceDate: 600_000)

    func makeStore() throws -> EveHistoryStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("EveHistoryStoreTests-\(UUID()).sqlite")
            .path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return try EveHistoryStore(path: path)
    }

    func samples(_ count: Int, from date: Date) -> [EveHistory.Sample] {
        (0 ..< count).map {
            EveHistory.Sample(date: date + TimeInterval($0) * EveHistory.interval, temperature: Float($0) / 4, humidity: 50 + Float($0 % 10))
        }
    }

    func testEmpty() async throws {
        let store = try makeStore()
        let histories = try await store.read()
        XCTAssertEqual(histories, [:])
        // nothing to save without entries
        try await store.save(EveHistory(), for: "A")
        let saved = try await store.read()
        XCTAssertEqual(saved, [:])
    }

    func testSaveAndRead() async throws {
        let store = try makeStore()
        var a = EveHistory()
        a.append(averaging: samples(10, from: start), now: .distantFuture)
        var b = EveHistory()
        b.append(averaging: samples(3, from: start + 3600), now: .distantFuture)
        try await store.save(a, for: "A")
        try await store.save(b, for: "B")
        let histories = try await store.read()
        XCTAssertEqual(histories, ["A": a, "B": b])
        XCTAssertEqual(histories["A"]?.status, a.status)
        // reopening the file reads the same history
        let reopened = try EveHistoryStore(path: store.path)
        let reread = try await reopened.read()
        XCTAssertEqual(reread, ["A": a, "B": b])
    }

    func testSaveChanges() async throws {
        let store = try makeStore()
        var history = EveHistory()
        history.append(averaging: samples(10, from: start), now: .distantFuture)
        try await store.save(history, for: "A")
        let oldValue = history
        history.append(averaging: samples(10, from: start + 10 * EveHistory.interval), now: .distantFuture)
        try await store.save(history, replacing: oldValue, for: "A")
        let histories = try await store.read()
        XCTAssertEqual(histories["A"], history)
        XCTAssertEqual(histories["A"]?.entries.count, 20)
    }

    func testSaveWrapped() async throws {
        let store = try makeStore()
        let capacity = Int(EveHistory.memorySize) - 1
        var history = EveHistory()
        history.append(averaging: samples(capacity, from: start), now: .distantFuture)
        try await store.save(history, for: "A")
        let oldValue = history
        // the oldest entries are dropped once memory is full
        history.append(averaging: samples(100, from: start + TimeInterval(capacity) * EveHistory.interval), now: .distantFuture)
        XCTAssertEqual(history.entries.count, capacity)
        try await store.save(history, replacing: oldValue, for: "A")
        let histories = try await store.read()
        XCTAssertEqual(histories["A"], history)
    }

    func testMissingEntry() async throws {
        let store = try makeStore()
        var history = EveHistory()
        history.append(averaging: samples(10, from: start), now: .distantFuture)
        XCTAssertEqual(history.entries.map(\.index), Array(2 ... 11))
        // save entries 2-6, then 8-11 as if 7 had been saved
        let first = EveHistory(referenceDate: history.referenceDate!, entries: Array(history.entries.prefix(5)))
        let missing = EveHistory(referenceDate: history.referenceDate!, entries: Array(history.entries.prefix(6)))
        try await store.save(first, for: "A")
        try await store.save(history, replacing: missing, for: "A")
        // the sensor is deleted and its history downloaded again
        let histories = try await store.read()
        XCTAssertEqual(histories, [:])
        try await store.save(history, for: "A")
        let saved = try await store.read()
        XCTAssertEqual(saved, ["A": history])
    }
}
