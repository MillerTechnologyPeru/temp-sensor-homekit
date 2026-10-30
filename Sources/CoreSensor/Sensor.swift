//
//  Sensor.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import CoreModel

/// Bluetooth sensor bridged to HomeKit, written by the scanner and read by the HomeKit bridge.
///
/// Readings have the calibration from the configuration file applied. A value the sensor doesn't report is `nil`.
@Entity
public struct Sensor: Equatable, Hashable, Codable, Identifiable, Sendable {

    public let id: ID

    // MARK: Identity

    /// Sensor type, the ``SensorAdvertisement/sensorType`` of its advertisement.
    @Attribute
    public var type: String

    /// Identifier the scanner last reached the sensor by.
    @Attribute
    public var peripheral: String

    // MARK: Accessory Information

    @Attribute
    public var name: String

    @Attribute
    public var manufacturer: String

    @Attribute
    public var model: String

    @Attribute
    public var serialNumber: String

    /// Firmware version, once the sensor reports it.
    @Attribute
    public var firmwareRevision: String?

    // MARK: Readings

    /// Temperature in degrees Celsius.
    @Attribute
    public var temperature: Float?

    /// Relative humidity in percent.
    @Attribute
    public var humidity: Float?

    /// Pressure in pounds per square inch.
    @Attribute
    public var pressure: Float?

    // MARK: Battery

    /// Battery level in percent.
    @Attribute(.int16)
    public var batteryLevel: UInt8?

    /// Battery voltage in volts.
    @Attribute
    public var batteryVoltage: Float?

    @Attribute
    public var lowBattery: Bool?

    // MARK: Reachability

    /// Last time the scanner found the sensor.
    @Attribute
    public var lastSeen: Date

    // MARK: Eve History

    /// Time of the Eve history reference entry, once the first entry is stored.
    @Attribute
    public var historyReferenceDate: Date?

    /// Last time the sensor's own history was downloaded.
    @Attribute
    public var lastHistorySync: Date?

    public init(
        id: ID,
        type: String,
        peripheral: String,
        name: String,
        manufacturer: String,
        model: String,
        serialNumber: String,
        firmwareRevision: String? = nil,
        temperature: Float? = nil,
        humidity: Float? = nil,
        pressure: Float? = nil,
        batteryLevel: UInt8? = nil,
        batteryVoltage: Float? = nil,
        lowBattery: Bool? = nil,
        lastSeen: Date,
        historyReferenceDate: Date? = nil,
        lastHistorySync: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.peripheral = peripheral
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.firmwareRevision = firmwareRevision
        self.temperature = temperature
        self.humidity = humidity
        self.pressure = pressure
        self.batteryLevel = batteryLevel
        self.batteryVoltage = batteryVoltage
        self.lowBattery = lowBattery
        self.lastSeen = lastSeen
        self.historyReferenceDate = historyReferenceDate
        self.lastHistorySync = lastHistorySync
    }
}

public extension Sensor {

    /// Sensor type and serial number, `<type>/<serial number>`.
    struct ID: RawRepresentable, Equatable, Hashable, Codable, Sendable, ObjectIDConvertible, CustomStringConvertible {

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(type: String, serialNumber: String) {
            self.init(rawValue: type + "/" + serialNumber)
        }

        public var description: String {
            rawValue
        }
    }

    /// Latest reading, as of ``lastSeen``.
    var reading: ReadingBuffer.Reading? {
        temperature.map { ReadingBuffer.Reading(date: lastSeen, temperature: $0, humidity: humidity) }
    }
}
