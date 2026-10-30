//
//  ReadingBuffer.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import DequeModule

/// Recent readings of a sensor without its own history, averaged into ``EveHistory`` intervals.
///
/// Only readings that differ from the previous one are stored, in storage allocated once.
public struct ReadingBuffer: Equatable, Sendable {

    /// Maximum number of readings stored.
    public let capacity: Int

    /// Readings not yet averaged, oldest first.
    public private(set) var readings: Deque<Reading>

    /// Reading in effect before the first stored reading.
    public private(set) var previous: Reading?

    /// Start of the next interval to average.
    public private(set) var nextInterval: Date

    /// - Parameters:
    ///   - start: Time from which to average readings. Intervals before it are skipped.
    ///   - previous: Last known reading, used until a newer one is appended.
    public init(capacity: Int = Self.defaultCapacity, start: Date, previous: Reading? = nil) {
        precondition(capacity > 0, "Capacity must be greater than zero")
        var readings = Deque<Reading>()
        readings.reserveCapacity(capacity)
        self.capacity = capacity
        self.readings = readings
        self.previous = previous
        self.nextInterval = Self.intervalStart(of: start)
    }
}

public extension ReadingBuffer {

    /// Two 10 minute intervals of one reading per second.
    static var defaultCapacity: Int { 1200 }

    struct Reading: Equatable, Hashable, Sendable {

        public let date: Date

        /// Temperature in degrees Celsius.
        public let temperature: Float

        /// Relative humidity in percent, if the sensor has one.
        public let humidity: Float?

        public init(date: Date, temperature: Float, humidity: Float? = nil) {
            self.date = date
            self.temperature = temperature
            self.humidity = humidity
        }

        /// Whether both readings have the same values.
        func hasSameValues(as other: Reading) -> Bool {
            temperature == other.temperature && humidity == other.humidity
        }
    }

    /// Newest reading, stored or previous.
    var last: Reading? {
        readings.last ?? previous
    }

    /// Stores a reading if its values differ from the last one.
    ///
    /// Once full, the oldest reading is dropped, so the storage never grows.
    ///
    /// - Returns: Whether the reading was stored.
    @discardableResult
    mutating func append(_ reading: Reading) -> Bool {
        if let last {
            guard reading.date > last.date, reading.hasSameValues(as: last) == false else {
                return false
            }
        }
        if readings.count == capacity {
            previous = readings.removeFirst()
        }
        readings.append(reading)
        return true
    }

    /// Averages each complete interval up to `now`, removing the readings no longer needed.
    ///
    /// Each value is weighted by how long it lasted, until the next reading.
    /// An interval without new readings repeats the last value. Intervals before the first known value are skipped.
    ///
    /// - Returns: One sample per interval, dated at the end of the interval.
    mutating func averages(through now: Date) -> [EveHistory.Sample] {
        var samples = [EveHistory.Sample]()
        let interval = EveHistory.interval
        while nextInterval + interval <= now {
            let start = nextInterval
            let end = start + interval
            if let sample = average(from: start, to: end) {
                samples.append(sample)
            }
            nextInterval = end
            // readings before the next interval are only needed for the value at its start
            while let first = readings.first, first.date <= end {
                previous = readings.removeFirst()
            }
        }
        return samples
    }
}

internal extension ReadingBuffer {

    /// Start of the interval containing `date`, aligned like ``EveHistory/append(averaging:now:)``.
    static func intervalStart(of date: Date) -> Date {
        let interval = EveHistory.interval
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval)
    }
}

private extension ReadingBuffer {

    func average(from start: Date, to end: Date) -> EveHistory.Sample? {
        var current = previous
        var segmentStart = start
        var duration: TimeInterval = 0
        var temperature: Double = 0
        var humidity: Double = 0
        var humidityDuration: TimeInterval = 0
        func add(_ reading: Reading?, until segmentEnd: Date) {
            guard let reading, segmentEnd > segmentStart else {
                return
            }
            let length = segmentEnd.timeIntervalSince(segmentStart)
            duration += length
            temperature += Double(reading.temperature) * length
            if let value = reading.humidity {
                humidity += Double(value) * length
                humidityDuration += length
            }
        }
        for reading in readings where reading.date < end {
            guard reading.date > start else {
                current = reading
                continue
            }
            add(current, until: reading.date)
            current = reading
            segmentStart = reading.date
        }
        add(current, until: end)
        guard duration > 0 else {
            return nil
        }
        return EveHistory.Sample(
            date: end,
            temperature: Float(temperature / duration),
            humidity: humidityDuration > 0 ? Float(humidity / humidityDuration) : 0
        )
    }
}
