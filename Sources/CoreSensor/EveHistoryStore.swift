//
//  EveHistoryStore.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import CoreModel
import CoreModelSQLite

/// Eve history of each sensor, stored in a SQLite database.
public actor EveHistoryStore {

    public nonisolated let path: String

    private let database: SQLiteDatabase

    /// Opens or creates the database at `path`.
    public init(path: String) throws {
        self.path = path
        self.database = try SQLiteDatabase(path: path, model: Self.model)
    }
}

public extension EveHistoryStore {

    static var model: Model {
        Model(entities: SensorHistory.self, SensorHistoryEntry.self)
    }

    /// Reads the history of every sensor.
    ///
    /// A sensor whose stored entries are missing one is deleted, so its history is downloaded again.
    func read() async throws -> [String: EveHistory] {
        let sensors = try await database.fetch(SensorHistory.self)
        let entries = Dictionary(grouping: try await database.fetch(SensorHistoryEntry.self), by: \.sensor)
        var histories = [String: EveHistory]()
        for sensor in sensors {
            let stored = (entries[sensor.id.rawValue] ?? []).sorted { $0.index < $1.index }
            // entries older than the memory size remain if a save was interrupted
            let newest = stored
                .suffix(Int(EveHistory.memorySize) - 1)
                .map { EveHistory.Entry(index: $0.index, date: $0.date, temperature: $0.temperature, humidity: $0.humidity) }
            guard Self.isValid(newest) else {
                try await database.delete(SensorHistoryEntry.entityName, for: stored.map { ObjectID($0.id) })
                try await database.delete(SensorHistory.self, for: sensor.id)
                continue
            }
            histories[sensor.id.rawValue] = EveHistory(referenceDate: sensor.referenceDate, entries: Array(newest))
        }
        return histories
    }

    /// Saves the changes to a sensor's history since `oldValue`, the history last saved for it.
    ///
    /// Inserts the entries newer than `oldValue` and deletes the entries no longer in `newValue`.
    func save(_ newValue: EveHistory, replacing oldValue: EveHistory = EveHistory(), for sensor: String) async throws {
        guard let referenceDate = newValue.referenceDate else {
            return
        }
        let entries: [EveHistory.Entry] = newValue.entries
        let inserted = try entries
            .filter { $0.index > oldValue.lastIndex }
            .map {
                try SensorHistoryEntry(
                    id: SensorHistoryEntry.ID(sensor: sensor, index: $0.index),
                    sensor: sensor,
                    index: $0.index,
                    date: $0.date,
                    temperature: $0.temperature,
                    humidity: $0.humidity
                ).encode()
            }
        let firstIndex = entries.first?.index ?? 0
        let oldEntries: [EveHistory.Entry] = oldValue.entries
        let deleted = oldEntries
            .filter { $0.index < firstIndex }
            .map { ObjectID(SensorHistoryEntry.ID(sensor: sensor, index: $0.index)) }
        // write new entries before dropping old ones, so an interrupted save only leaves extra old entries
        try await database.insert(inserted)
        try await database.insert(SensorHistory(id: SensorHistory.ID(rawValue: sensor), referenceDate: referenceDate))
        if deleted.isEmpty == false {
            try await database.delete(SensorHistoryEntry.entityName, for: deleted)
        }
    }
}

private extension EveHistoryStore {

    /// Whether the entries have consecutive indices, starting where ``EveHistory`` expects.
    static func isValid(_ entries: [EveHistory.Entry]) -> Bool {
        guard let first = entries.first, let last = entries.last else {
            return true
        }
        let memorySize = UInt32(EveHistory.memorySize)
        // index 1 is the reference entry, or the oldest slot once memory wraps
        let firstIndex = last.index < memorySize ? 2 : last.index - memorySize + 2
        return first.index == firstIndex && last.index - first.index + 1 == UInt32(entries.count)
    }
}

// MARK: - Entities

/// Sensor with stored Eve history.
@Entity
struct SensorHistory: Equatable, Hashable, Codable, Identifiable, Sendable {

    let id: ID

    /// Time of the reference entry. Entry times sent to Eve are relative to it.
    @Attribute
    var referenceDate: Date

    init(id: ID, referenceDate: Date) {
        self.id = id
        self.referenceDate = referenceDate
    }
}

/// Entry in a sensor's Eve history.
@Entity
struct SensorHistoryEntry: Equatable, Hashable, Codable, Identifiable, Sendable {

    let id: ID

    /// History identifier of the sensor.
    @Attribute
    var sensor: String

    @Attribute(.int64)
    var index: UInt32

    @Attribute
    var date: Date

    /// Temperature in degrees Celsius.
    @Attribute
    var temperature: Float

    /// Relative humidity in percent.
    @Attribute
    var humidity: Float

    init(id: ID, sensor: String, index: UInt32, date: Date, temperature: Float, humidity: Float) {
        self.id = id
        self.sensor = sensor
        self.index = index
        self.date = date
        self.temperature = temperature
        self.humidity = humidity
    }
}

extension SensorHistory {

    /// History identifier of the sensor.
    struct ID: RawRepresentable, Equatable, Hashable, Codable, Sendable, ObjectIDConvertible {

        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        var description: String {
            rawValue
        }
    }
}

extension SensorHistoryEntry {

    /// Sensor history identifier and entry index.
    struct ID: RawRepresentable, Equatable, Hashable, Codable, Sendable, ObjectIDConvertible {

        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(sensor: String, index: UInt32) {
            self.init(rawValue: sensor + "/" + index.description)
        }

        var description: String {
            rawValue
        }
    }
}
