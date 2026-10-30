//
//  SensorKind.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import Bluetooth
import GATT
import CoreSensor
import Govee
import Inkbird
import TPMS
import XiaomiBluetooth

/// Supported sensor models and the HomeKit services they provide.
enum SensorKind: CaseIterable {

    case ge
    case govee
    case inkbird
    case tirePressure
    case xiaomi
}

extension SensorKind {

    /// How a sensor's Eve history is obtained.
    enum HistorySource {

        /// Downloaded from the sensor's own memory.
        case downloaded

        /// Recorded by the bridge from the sensor's readings.
        case recorded
    }

    init?(type: String) {
        guard let kind = Self.allCases.first(where: { $0.type == type }) else {
            return nil
        }
        self = kind
    }

    /// The ``Sensor/type`` of this kind of sensor.
    var type: String {
        switch self {
        case .ge:
            return GETemperatureSensor.sensorType
        case .govee:
            return GoveeAccessory.Thermometer.sensorType
        case .inkbird:
            return InkbirdAdvertisement.Thermometer.sensorType
        case .tirePressure:
            return TirePressureSensor.sensorType
        case .xiaomi:
            return MiBeacon.sensorType
        }
    }

    var defaultName: String {
        switch self {
        case .ge:
            return "GE Thermometer Sensor"
        case .govee:
            return "Govee Thermometer Sensor"
        case .inkbird:
            return "Inkbird Thermometer Sensor"
        case .tirePressure:
            return "Tire Pressure Monitoring System Sensor"
        case .xiaomi:
            return "Xiaomi Thermometer Sensor"
        }
    }

    var manufacturer: String {
        switch self {
        case .ge:
            return "GE"
        case .govee:
            return "Shenzhen Intellirocks Tech. Co., Ltd."
        case .inkbird:
            return "Inkbird"
        case .tirePressure:
            return "TPMS"
        case .xiaomi:
            return "Xiaomi"
        }
    }

    var hasHumidity: Bool {
        self != .tirePressure
    }

    var hasPressure: Bool {
        self == .tirePressure
    }

    var hasBatteryVoltage: Bool {
        self == .ge || self == .xiaomi
    }

    var historySource: HistorySource {
        switch self {
        case .govee, .inkbird:
            return .downloaded
        case .ge, .tirePressure, .xiaomi:
            return .recorded
        }
    }

    var historyFields: EveHistory.Fields {
        hasHumidity ? .temperatureHumidity : .temperature
    }
}

// MARK: - Values

/// Values read from a sensor, before calibration. `nil` for values not read.
struct SensorValues: Equatable {

    var temperature: Float?

    var humidity: Float?

    var pressure: Float?

    var batteryLevel: UInt8?

    var batteryVoltage: Float?

    var firmwareRevision: String?
}

extension Sensor {

    /// Battery level below which the battery is reported as low.
    static var lowBatteryLevel: UInt8 { 25 }

    /// Updates the values that were read, applying the calibration to the readings.
    mutating func update(_ values: SensorValues, calibration: SensorConfiguration.Calibration?) {
        if let value = values.temperature {
            temperature = value + (calibration?.temperature ?? 0)
        }
        if let value = values.humidity {
            humidity = value + (calibration?.humidity ?? 0)
        }
        if let value = values.pressure {
            pressure = value
        }
        if let value = values.batteryLevel {
            batteryLevel = value
            lowBattery = value < Self.lowBatteryLevel
        }
        if let value = values.batteryVoltage {
            batteryVoltage = value
        }
        if let value = values.firmwareRevision {
            firmwareRevision = value
        }
    }
}

// MARK: - Advertisements

/// Advertisement of a sensor bridged to HomeKit.
protocol BridgedSensorAdvertisement: SensorAdvertisement {

    static var kind: SensorKind { get }

    /// Serial number shown in HomeKit, which also keeps the accessory's HomeKit identifier.
    func serialNumber(peripheral: NativeCentral.Peripheral) -> String

    /// Model shown in HomeKit.
    var modelName: String { get }

    /// Values in the advertisement.
    var values: SensorValues { get }
}

extension GETemperatureSensor: BridgedSensorAdvertisement {

    static var kind: SensorKind { .ge }

    func serialNumber(peripheral: NativeCentral.Peripheral) -> String {
        peripheral.description
    }

    var modelName: String {
        model.description
    }

    var values: SensorValues {
        SensorValues(
            temperature: temperatureCelcius,
            humidity: humidityPercentage,
            batteryLevel: UInt8(batteryLevel.rounded()),
            batteryVoltage: batteryVoltage,
            firmwareRevision: "\(version)"
        )
    }
}

extension GoveeAccessory.Thermometer: BridgedSensorAdvertisement {

    public static var sensorType: String { "com.Govee.Thermometer" }

    static var kind: SensorKind { .govee }

    func serialNumber(peripheral: NativeCentral.Peripheral) -> String {
        id.rawValue
    }

    var modelName: String {
        id.model.rawValue
    }

    var values: SensorValues {
        SensorValues(
            temperature: temperature,
            humidity: humidity,
            batteryLevel: batteryLevel
        )
    }
}

extension InkbirdAdvertisement.Thermometer: BridgedSensorAdvertisement {

    public static var sensorType: String { "com.Inkbird.Thermometer" }

    static var kind: SensorKind { .inkbird }

    func serialNumber(peripheral: NativeCentral.Peripheral) -> String {
        peripheral.description
    }

    var modelName: String {
        name.rawValue
    }

    var values: SensorValues {
        SensorValues(
            temperature: manufacturingData.temperature.celcius,
            humidity: manufacturingData.humidity.percentage,
            batteryLevel: manufacturingData.batteryLevel.rawValue
        )
    }
}

extension TirePressureSensor: BridgedSensorAdvertisement {

    public static var sensorType: String { "com.TPMS.Sensor" }

    static var kind: SensorKind { .tirePressure }

    func serialNumber(peripheral: NativeCentral.Peripheral) -> String {
        address.rawValue
    }

    var modelName: String {
        "TPMS"
    }

    var values: SensorValues {
        SensorValues(
            temperature: temperature.celsius,
            pressure: Float(pressure.poundPerSquareInch),
            batteryLevel: batteryLevel.rawValue
        )
    }
}

extension MiBeacon: BridgedSensorAdvertisement {

    public static var sensorType: String { "com.Xiaomi.Thermometer" }

    static var kind: SensorKind { .xiaomi }

    func serialNumber(peripheral: NativeCentral.Peripheral) -> String {
        address?.rawValue ?? peripheral.description
    }

    var modelName: String {
        product.description
    }

    /// Readings are read from a connection instead.
    var values: SensorValues {
        SensorValues()
    }
}
