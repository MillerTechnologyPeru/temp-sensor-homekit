//
//  SensorConnection.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import Bluetooth
import BluetoothGATT
import GATT
import CoreSensor
import Govee
import Inkbird
import XiaomiBluetooth

/// Readings downloaded from a sensor's own history.
struct HistoryDownload {

    /// Time of the download.
    let date: Date

    /// Readings, before calibration.
    let samples: [EveHistory.Sample]

    /// Firmware version, if it was read.
    let firmwareRevision: String?
}

/// Time allowed to establish the Bluetooth connection for a history download.
///
/// A connection attempt that times out stays queued for the peripheral, so keep this generous.
private var syncConnectTimeout: TimeInterval { 30 }

/// Time allowed for each reply, and between history records, during a download.
private var syncReplyTimeout: TimeInterval { 10 }

// MARK: - Govee

enum GoveeThermometer {

    /// Time between history downloads.
    static var syncInterval: TimeInterval { 30 * 60 }

    /// Longest history requested in one download.
    static var maxHistoryMinutes: TimeInterval { 24 * 60 }

    /// Connects to the thermometer, reads its firmware version and downloads the readings since `lastDate`.
    static func download(
        central: NativeCentral,
        peripheral: NativeCentral.Peripheral,
        model: GoveeModel,
        after lastDate: Date?,
        readFirmware: Bool
    ) async throws -> HistoryDownload {
        let connection = try await central.connect(
            to: peripheral,
            model: model,
            connectTimeout: syncConnectTimeout,
            timeout: syncReplyTimeout
        )
        do {
            let result = try await download(connection: connection, after: lastDate, readFirmware: readFirmware)
            await connection.disconnect()
            return result
        }
        catch {
            await connection.disconnect()
            throw error
        }
    }

    private static func download(
        connection: GoveeConnection<NativeCentral>,
        after lastDate: Date?,
        readFirmware: Bool
    ) async throws -> HistoryDownload {
        var firmwareRevision: String?
        if readFirmware {
            firmwareRevision = try await connection.send(GoveeQuery.thermometerFirmwareVersion, timeout: syncReplyTimeout).thermometerFirmwareVersion
        }
        // download minutes since the last entry
        let now = Date()
        // the H5072 disconnects partway through long downloads (after about 600 frames, 2.5 days)
        let maxMinutes = maxHistoryMinutes
        let minutes = lastDate.map { (now.timeIntervalSince($0) / 60).rounded(.up) } ?? maxMinutes
        guard minutes >= EveHistory.interval / 60 else {
            return HistoryDownload(date: now, samples: [], firmwareRevision: firmwareRevision)
        }
        let readings = try await connection.thermometerHistory(minutes: UInt16(min(minutes, maxMinutes)), timeout: syncReplyTimeout)
        let samples = readings.map {
            EveHistory.Sample(
                date: now - TimeInterval($0.minutesAgo) * 60,
                temperature: $0.temperature,
                humidity: $0.humidity
            )
        }
        return HistoryDownload(date: now, samples: samples, firmwareRevision: firmwareRevision)
    }
}

// MARK: - Inkbird

enum InkbirdThermometer {

    /// Time between history downloads. Each download reads the whole buffer, about 90 seconds.
    static var syncInterval: TimeInterval { 60 * 60 }

    /// Connects to the sensor and downloads its stored history.
    static func download(
        central: NativeCentral,
        peripheral: NativeCentral.Peripheral
    ) async throws -> HistoryDownload {
        let connection = try await central.connect(
            to: peripheral,
            model: .ibsTH2,
            connectTimeout: syncConnectTimeout,
            timeout: syncReplyTimeout
        )
        let readings: [InkbirdHistoryReading]
        do {
            readings = try await connection.history(timeout: syncReplyTimeout)
        }
        catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
        let samples = readings.map {
            EveHistory.Sample(
                date: $0.date,
                temperature: $0.temperature,
                humidity: $0.humidity
            )
        }
        return HistoryDownload(date: Date(), samples: samples, firmwareRevision: nil)
    }
}

// MARK: - Xiaomi

enum XiaomiThermometer {

    /// Reads the thermometer's temperature, humidity, battery and firmware version.
    static func read(_ connection: GATTConnection<NativeCentral>) async throws -> SensorValues {
        var values = SensorValues()
        // search for characteristic
        guard let temperatureCharacteristic = connection.cache.characteristic(TemperatureHumidityCharacteristic.uuid, service: TemperatureHumidityCharacteristic.service) else {
            throw TempSensorHomeKitToolError.characteristicNotFound(TemperatureHumidityCharacteristic.uuid)
        }
        // read and parse data
        let data = try await connection.central.readValue(for: temperatureCharacteristic)
        guard let temperatureCharacteristicValue = TemperatureHumidityCharacteristic(data: data) else {
            throw TempSensorHomeKitToolError.invalidCharacteristicValue(TemperatureHumidityCharacteristic.uuid)
        }
        values.batteryVoltage = Float(temperatureCharacteristicValue.batteryVoltage.voltage)
        values.temperature = temperatureCharacteristicValue.temperature.celcius
        values.humidity = Float(temperatureCharacteristicValue.humidity.rawValue)
        // read battery level
        if let characteristic = connection.cache.characteristic(GATTBatteryLevel.uuid, service: BluetoothUUID.Service.battery) {
            let data = try await connection.central.readValue(for: characteristic)
            guard let value = BluetoothGATT.GATTBatteryLevel(data: data) else {
                throw TempSensorHomeKitToolError.invalidCharacteristicValue(GATTBatteryLevel.uuid)
            }
            values.batteryLevel = value.level.rawValue
        }
        // read information
        if let characteristic = connection.cache.characteristic(GATTFirmwareRevisionString.uuid, service: BluetoothUUID.Service.deviceInformation) {
            let data = try await connection.central.readValue(for: characteristic)
            guard let value = GATTFirmwareRevisionString(data: data) else {
                throw TempSensorHomeKitToolError.invalidCharacteristicValue(GATTFirmwareRevisionString.uuid)
            }
            values.firmwareRevision = value.rawValue
        }
        return values
    }
}
