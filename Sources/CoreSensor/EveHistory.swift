//
//  EveHistory.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation

/// Temperature and humidity log in the format the Eve app downloads from the Eve history service.
///
/// Uses the fakegato-history "custom" layout with temperature, and optionally humidity, fields.
/// See https://github.com/simont77/fakegato-history
public struct EveHistory: Equatable, Hashable, Codable, Sendable {

    /// Fields in each entry.
    public let fields: Fields

    /// Time of the reference entry (index 1). Entry times are relative to it.
    public private(set) var referenceDate: Date?

    /// Stored entries, oldest first, with consecutive indices.
    public private(set) var entries: [Entry]

    public init(fields: Fields = .temperatureHumidity) {
        self.fields = fields
        self.referenceDate = nil
        self.entries = []
    }

    /// Restores a stored history.
    ///
    /// - Parameter entries: Entries with consecutive indices, oldest first.
    public init(fields: Fields = .temperatureHumidity, referenceDate: Date, entries: [Entry]) {
        assert(zip(entries, entries.dropFirst()).allSatisfy { $0.index + 1 == $1.index }, "Entries must have consecutive indices")
        self.fields = fields
        self.referenceDate = referenceDate
        self.entries = entries
    }
}

public extension EveHistory {

    /// Number of entries Eve is told the accessory can store, including the reference entry.
    static var memorySize: UInt16 { 4032 }

    /// Time covered by each entry.
    static var interval: TimeInterval { 600 }

    /// Maximum entries sent in one read of the history entries characteristic.
    static var entriesPerRead: Int { 11 }

    /// Fields stored in each entry.
    enum Fields: String, Equatable, Hashable, Codable, Sendable, CaseIterable {

        /// Temperature and relative humidity.
        case temperatureHumidity

        /// Temperature only, for sensors without humidity.
        case temperature
    }

    struct Entry: Equatable, Hashable, Codable, Sendable {

        public let index: UInt32

        public let date: Date

        /// Temperature in degrees Celsius.
        public let temperature: Float

        /// Relative humidity in percent, `0` without a humidity field.
        public let humidity: Float

        public init(index: UInt32, date: Date, temperature: Float, humidity: Float) {
            self.index = index
            self.date = date
            self.temperature = temperature
            self.humidity = humidity
        }
    }

    struct Sample: Equatable, Hashable, Sendable {

        public let date: Date

        /// Temperature in degrees Celsius.
        public let temperature: Float

        /// Relative humidity in percent.
        public let humidity: Float

        public init(date: Date, temperature: Float, humidity: Float) {
            self.date = date
            self.temperature = temperature
            self.humidity = humidity
        }
    }

    /// Index of the newest entry, or `0` if empty.
    var lastIndex: UInt32 {
        entries.last?.index ?? (referenceDate == nil ? 0 : 1)
    }

    /// Date of the newest entry.
    var lastDate: Date? {
        entries.last?.date
    }

    /// Appends an entry newer than the last one, dropping the oldest entries once memory is full.
    mutating func append(date: Date, temperature: Float, humidity: Float) {
        if let lastDate {
            precondition(date > lastDate, "Entries must be appended in order")
        }
        if referenceDate == nil {
            referenceDate = date
        }
        let entry = Entry(
            index: Swift.max(lastIndex, 1) + 1,
            date: date,
            temperature: temperature,
            humidity: humidity
        )
        entries.append(entry)
        // the reference entry, or the oldest slot once memory wraps, takes one entry
        let capacity = Int(Self.memorySize) - 1
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Averages samples into ``interval`` buckets and appends the complete buckets newer than the last entry.
    ///
    /// Each entry is dated at the end of its bucket. A bucket ending after `now` is still in progress and skipped.
    ///
    /// - Returns: The number of entries appended.
    @discardableResult
    mutating func append<S: Sequence>(averaging samples: S, now: Date = Date()) -> Int where S.Element == Sample {
        let buckets = Dictionary(grouping: samples) {
            Int64(($0.date.timeIntervalSinceReferenceDate / Self.interval).rounded(.down))
        }
        var count = 0
        for bucket in buckets.keys.sorted() {
            let date = Date(timeIntervalSinceReferenceDate: TimeInterval(bucket + 1) * Self.interval)
            guard date <= now else {
                continue
            }
            if let lastDate, date <= lastDate {
                continue
            }
            let values = buckets[bucket]!
            let temperature = values.reduce(0) { $0 + $1.temperature } / Float(values.count)
            let humidity = values.reduce(0) { $0 + $1.humidity } / Float(values.count)
            append(date: date, temperature: temperature, humidity: humidity)
            count += 1
        }
        return count
    }
}

// MARK: - Eve Encoding

public extension EveHistory {

    /// Value of the history status characteristic (`E863F116`).
    var status: Data {
        let lastIndex = self.lastIndex
        let usedMemory: UInt16
        let firstIndex: UInt32
        if referenceDate == nil {
            usedMemory = 0
            firstIndex = 0
        } else if lastIndex < UInt32(Self.memorySize) {
            usedMemory = UInt16(lastIndex + 1)
            firstIndex = 0
        } else {
            usedMemory = Self.memorySize
            firstIndex = lastIndex - UInt32(Self.memorySize) + 1
        }
        var data = Data()
        data.append(littleEndian: entries.last.map { offset(of: $0.date) } ?? 0)
        data.append(littleEndian: UInt32(0)) // negative offset
        data.append(littleEndian: referenceTime)
        data.append(contentsOf: fields.signature)
        data.append(littleEndian: usedMemory)
        data.append(littleEndian: Self.memorySize)
        data.append(littleEndian: firstIndex)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x01])
        return data
    }

    /// Index requested by a write to the history request characteristic (`E863F11C`).
    static func requestedIndex(_ data: Data) -> UInt32? {
        guard data.count >= 6 else {
            return nil
        }
        let bytes = [UInt8](data)
        return UInt32(bytes[2])
            | UInt32(bytes[3]) << 8
            | UInt32(bytes[4]) << 16
            | UInt32(bytes[5]) << 24
    }

    /// Entries for one read of the history entries characteristic (`E863F117`), starting at `index`.
    ///
    /// - Returns: The encoded entries and the index to continue from, or `nil` once there are no more entries.
    func entries(from index: UInt32, limit: Int = Self.entriesPerRead) -> (data: Data, next: UInt32)? {
        guard referenceDate != nil else {
            return nil
        }
        let lastIndex = self.lastIndex
        // oldest slot still in memory, sent as the reference entry
        let referenceIndex = lastIndex < UInt32(Self.memorySize) ? 1 : lastIndex - UInt32(Self.memorySize) + 1
        var index = Swift.max(index, referenceIndex)
        guard index <= lastIndex else {
            return nil
        }
        var data = Data()
        var count = 0
        while index <= lastIndex, count < limit {
            if index == referenceIndex {
                data.append(0x15)
                data.append(littleEndian: index)
                data.append(contentsOf: [0x01, 0x00, 0x00, 0x00, 0x81])
                data.append(littleEndian: referenceTime)
                data.append(contentsOf: [UInt8](repeating: 0x00, count: 7))
            } else {
                let entry = entries[Int(index - entries[0].index)]
                assert(entry.index == index)
                data.append(fields.entryLength)
                data.append(littleEndian: index)
                data.append(littleEndian: offset(of: entry.date))
                data.append(fields.entryType)
                data.append(littleEndian: Int16((entry.temperature * 100).rounded()))
                if fields == .temperatureHumidity {
                    data.append(littleEndian: UInt16((Swift.min(Swift.max(entry.humidity, 0), 100) * 100).rounded()))
                }
            }
            index += 1
            count += 1
        }
        return (data, index)
    }
}

internal extension EveHistory.Fields {

    /// Fields in each entry: temperature (`0102`) and humidity (`0202`), 2 bytes each.
    var signature: [UInt8] {
        switch self {
        case .temperatureHumidity:
            return [0x02, 0x01, 0x02, 0x02, 0x02]
        case .temperature:
            return [0x01, 0x01, 0x02]
        }
    }

    /// Bitmask of the fields present in each entry.
    var entryType: UInt8 {
        switch self {
        case .temperatureHumidity:
            return 0x03
        case .temperature:
            return 0x01
        }
    }

    /// Length of each encoded entry, including the length byte.
    var entryLength: UInt8 {
        switch self {
        case .temperatureHumidity:
            return 0x0E
        case .temperature:
            return 0x0C
        }
    }
}

private extension EveHistory {

    /// Reference time in seconds since 2001-01-01.
    var referenceTime: UInt32 {
        referenceDate.map { UInt32($0.timeIntervalSinceReferenceDate) } ?? 0
    }

    /// Seconds since the reference time.
    func offset(of date: Date) -> UInt32 {
        UInt32(Swift.max(date.timeIntervalSinceReferenceDate.rounded(.down) - TimeInterval(referenceTime), 0))
    }
}

private extension Data {

    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
