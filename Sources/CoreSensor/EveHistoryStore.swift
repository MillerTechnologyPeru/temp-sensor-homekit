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
///
/// Keeps up to ``limit`` entries per sensor, more than the Eve history memory holds.
public actor EveHistoryStore {

    public nonisolated let path: String

    /// Maximum number of entries stored for each sensor. Older entries are deleted.
    public nonisolated let limit: UInt

    internal let database: SQLiteDatabase

    /// Opens or creates the database at `path`.
    public init(path: String, limit: UInt = EveHistoryStore.defaultLimit) throws {
        self.path = path
        self.limit = limit
        self.database = try SQLiteDatabase(path: path, model: Self.model)
    }
}

public extension EveHistoryStore {

    /// Default number of entries stored for each sensor, almost two years of 10 minute entries.
    static var defaultLimit: UInt { 100_000 }

    static var model: Model {
        Model(entities: SensorHistory.self, SensorHistoryEntry.self)
    }

    /// Reads the newest entries of every sensor, as many as the Eve history memory holds.
    ///
    /// A sensor whose newest entries are missing one is deleted, so its history is downloaded again.
    func read() async throws -> [String: EveHistory] {
        let sensors = try await database.fetch(SensorHistory.self)
        var histories = [String: EveHistory]()
        for sensor in sensors {
            let stored = try await database.fetch(
                SensorHistoryEntry.self,
                sortDescriptors: [.init(property: PropertyKey(SensorHistoryEntry.CodingKeys.index), ascending: false)],
                predicate: SensorHistoryEntry.CodingKeys.sensor == sensor.id.rawValue,
                fetchLimit: Int(EveHistory.memorySize) - 1
            )
            let newest = stored
                .reversed()
                .map { EveHistory.Entry(index: $0.index, date: $0.date, temperature: $0.temperature, humidity: $0.humidity) }
            guard Self.isValid(newest) else {
                try await delete(sensor: sensor.id)
                continue
            }
            histories[sensor.id.rawValue] = EveHistory(referenceDate: sensor.referenceDate, entries: newest)
        }
        return histories
    }

    /// Saves the entries newer than `oldValue`, the history last saved for the sensor,
    /// and deletes the entries over ``limit``.
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
        try await database.insert(inserted)
        try await database.insert(SensorHistory(id: SensorHistory.ID(rawValue: sensor), referenceDate: referenceDate))
        // indices are consecutive, so the entries over the limit are the ones at or below this index
        let lastIndex = newValue.lastIndex
        guard UInt(lastIndex) > limit else {
            return
        }
        let deleted = try await database.fetchID(FetchRequest(
            entity: SensorHistoryEntry.entityName,
            predicate: SensorHistoryEntry.CodingKeys.sensor == sensor
                && SensorHistoryEntry.CodingKeys.index <= Int64(lastIndex) - Int64(limit)
        ))
        if deleted.isEmpty == false {
            try await database.delete(SensorHistoryEntry.entityName, for: deleted)
        }
    }
}

private extension EveHistoryStore {

    /// Deletes a sensor and all its entries.
    func delete(sensor: SensorHistory.ID) async throws {
        let entries = try await database.fetchID(FetchRequest(
            entity: SensorHistoryEntry.entityName,
            predicate: SensorHistoryEntry.CodingKeys.sensor == sensor.rawValue
        ))
        try await database.delete(SensorHistoryEntry.entityName, for: entries)
        try await database.delete(SensorHistory.self, for: sensor)
    }

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
