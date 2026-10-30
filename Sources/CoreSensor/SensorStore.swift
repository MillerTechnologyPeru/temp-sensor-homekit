//
//  SensorStore.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import CoreModel
import CoreModelSQLite

/// Sensors and their Eve history, stored in a SQLite database.
///
/// The scanner writes sensors and history here, and the HomeKit bridge reads them,
/// following ``changes`` for updates.
///
/// Keeps up to ``limit`` history entries per sensor, more than the Eve history memory holds.
public actor SensorStore {

    public nonisolated let path: String

    /// Maximum number of history entries stored for each sensor. Older entries are deleted.
    public nonisolated let limit: UInt

    /// Changes written to the store, in order.
    public nonisolated let changes: AsyncStream<Change>

    internal let database: SQLiteDatabase

    private let continuation: AsyncStream<Change>.Continuation

    /// Opens or creates the database at `path`.
    public init(path: String, limit: UInt = SensorStore.defaultLimit) throws {
        self.path = path
        self.limit = limit
        self.database = try SQLiteDatabase(path: path, model: Self.model)
        (self.changes, self.continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit {
        continuation.finish()
    }
}

public extension SensorStore {

    /// Default number of history entries stored for each sensor, almost two years of 10 minute entries.
    static var defaultLimit: UInt { 100_000 }

    static var model: Model {
        Model(entities: Sensor.self, SensorHistoryEntry.self)
    }

    enum Change: Equatable, Sendable {

        /// A sensor was created or updated.
        case sensor(Sensor)

        /// Entries were added to a sensor's history.
        case history(Sensor.ID, EveHistory)
    }

    /// All stored sensors.
    func sensors() async throws -> [Sensor] {
        try await database.fetch(Sensor.self)
    }

    func sensor(for id: Sensor.ID) async throws -> Sensor? {
        try await database.fetch(Sensor.self, for: id)
    }

    /// Creates or updates a sensor.
    ///
    /// The history reference date is kept, since only ``saveHistory(_:replacing:for:)`` changes it.
    func update(_ sensor: Sensor) async throws {
        var sensor = sensor
        sensor.historyReferenceDate = try await database.fetch(Sensor.self, for: sensor.id)?.historyReferenceDate
        try await database.insert(sensor)
        continuation.yield(.sensor(sensor))
    }

    /// Reads the newest history entries of a sensor, as many as the Eve history memory holds.
    ///
    /// If the newest entries are missing one, they are deleted, so the history is downloaded or recorded again.
    func history(for id: Sensor.ID, fields: EveHistory.Fields = .temperatureHumidity) async throws -> EveHistory {
        guard let sensor = try await database.fetch(Sensor.self, for: id),
              let referenceDate = sensor.historyReferenceDate else {
            return EveHistory(fields: fields)
        }
        let stored = try await database.fetch(
            SensorHistoryEntry.self,
            sortDescriptors: [.init(property: PropertyKey(SensorHistoryEntry.CodingKeys.index), ascending: false)],
            predicate: SensorHistoryEntry.CodingKeys.sensor == id.rawValue,
            fetchLimit: Int(EveHistory.memorySize) - 1
        )
        let newest = stored
            .reversed()
            .map { EveHistory.Entry(index: $0.index, date: $0.date, temperature: $0.temperature, humidity: $0.humidity) }
        guard Self.isValid(newest) else {
            try await deleteHistory(of: sensor)
            return EveHistory(fields: fields)
        }
        return EveHistory(fields: fields, referenceDate: referenceDate, entries: newest)
    }

    /// Saves the entries newer than `oldValue`, the history last saved for the sensor,
    /// and deletes the entries over ``limit``.
    ///
    /// The sensor must already be stored.
    func saveHistory(_ newValue: EveHistory, replacing oldValue: EveHistory, for id: Sensor.ID) async throws {
        guard let referenceDate = newValue.referenceDate,
              var sensor = try await database.fetch(Sensor.self, for: id) else {
            return
        }
        let entries: [EveHistory.Entry] = newValue.entries
        let inserted = try entries
            .filter { $0.index > oldValue.lastIndex }
            .map {
                try SensorHistoryEntry(
                    id: SensorHistoryEntry.ID(sensor: id, index: $0.index),
                    sensor: id.rawValue,
                    index: $0.index,
                    date: $0.date,
                    temperature: $0.temperature,
                    humidity: $0.humidity
                ).encode()
            }
        try await database.insert(inserted)
        if sensor.historyReferenceDate != referenceDate {
            sensor.historyReferenceDate = referenceDate
            try await database.insert(sensor)
            continuation.yield(.sensor(sensor))
        }
        continuation.yield(.history(id, newValue))
        // indices are consecutive, so the entries over the limit are the ones at or below this index
        let lastIndex = newValue.lastIndex
        guard UInt(lastIndex) > limit else {
            return
        }
        let deleted = try await database.fetchID(FetchRequest(
            entity: SensorHistoryEntry.entityName,
            predicate: SensorHistoryEntry.CodingKeys.sensor == id.rawValue
                && SensorHistoryEntry.CodingKeys.index <= Int64(lastIndex) - Int64(limit)
        ))
        if deleted.isEmpty == false {
            try await database.delete(SensorHistoryEntry.entityName, for: deleted)
        }
    }

    /// Number of history entries stored for a sensor.
    func historyCount(for id: Sensor.ID) async throws -> UInt {
        try await database.count(FetchRequest(
            entity: SensorHistoryEntry.entityName,
            predicate: SensorHistoryEntry.CodingKeys.sensor == id.rawValue
        ))
    }
}

private extension SensorStore {

    /// Deletes all history entries of a sensor.
    func deleteHistory(of sensor: Sensor) async throws {
        let entries = try await database.fetchID(FetchRequest(
            entity: SensorHistoryEntry.entityName,
            predicate: SensorHistoryEntry.CodingKeys.sensor == sensor.id.rawValue
        ))
        try await database.delete(SensorHistoryEntry.entityName, for: entries)
        var sensor = sensor
        sensor.historyReferenceDate = nil
        try await database.insert(sensor)
        continuation.yield(.sensor(sensor))
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

/// Entry in a sensor's Eve history.
@Entity
struct SensorHistoryEntry: Equatable, Hashable, Codable, Identifiable, Sendable {

    let id: ID

    /// Identifier of the sensor.
    @Attribute
    var sensor: String

    @Attribute(.int64)
    var index: UInt32

    @Attribute
    var date: Date

    /// Temperature in degrees Celsius.
    @Attribute
    var temperature: Float

    /// Relative humidity in percent, `0` for sensors without humidity.
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

extension SensorHistoryEntry {

    /// Sensor identifier and entry index.
    struct ID: RawRepresentable, Equatable, Hashable, Codable, Sendable, ObjectIDConvertible {

        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(sensor: Sensor.ID, index: UInt32) {
            self.init(rawValue: sensor.rawValue + "/" + index.description)
        }

        var description: String {
            rawValue
        }
    }
}
