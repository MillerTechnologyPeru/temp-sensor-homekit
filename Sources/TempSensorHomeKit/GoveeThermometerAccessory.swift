//
//  GoveeThermometerAccessory.swift
//  
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Govee
import CoreSensor

final class GoveeThermometerAccessory: HAP.Accessory.Thermometer, SensorAccessory {
    
    let peripheral: NativeCentral.Peripheral
    
    private(set) var lastSeen: Date = Date()
    
    let configuration: SensorConfiguration.Sensor?
    
    //let bridgeState: AccessoryBridgingState
    
    let humidity = HAP.Service.HumiditySensor()
    
    let battery = BatteryService()
    
    let history = EveHistoryService()
    
    let model: GoveeModel
    
    let historyIdentifier: String
    
    /// Last time the history was downloaded.
    private(set) var lastSync: Date?
    
    /// Last time a history download failed.
    private(set) var lastSyncFailure: Date?
    
    init(peripheral: NativeCentral.Peripheral, advertisement: GoveeAccessory.Thermometer, configuration: SensorConfiguration.Sensor?) {
        self.peripheral = peripheral
        self.configuration = configuration
        self.model = advertisement.id.model
        self.historyIdentifier = advertisement.id.rawValue
        let id = advertisement.id.rawValue
        let info = Service.Info.Info(
            name: configuration?.name ?? "Govee Thermometer Sensor",
            serialNumber: id,
            manufacturer: "Shenzhen Intellirocks Tech. Co., Ltd.",
            model: configuration?.model ?? advertisement.id.model.rawValue,
            firmwareRevision: Self.defaultFirmwareRevision
        )/*
        self.bridgeState = AccessoryBridgingState(
            reachable: true,
            linkQuality: 0,
            accessoryIdentifier: id,
            category: 0
        )*/
        super.init(
            info: info,
            additionalServices: [
                //bridgeState,
                humidity,
                battery,
                history
            ]
        )
        self.update(advertisement: advertisement)
    }
    
    func update(advertisement: GoveeAccessory.Thermometer) {
        self.lastSeen = Date()
        self.reachable = true
        self.battery.batteryLevel?.value = advertisement.batteryLevel
        self.battery.statusLowBattery.value = advertisement.batteryLevel < 25 ? .batteryLow : .batteryNormal
        self.temperatureSensor.currentTemperature.value = advertisement.temperature + (configuration?.calibration?.temperature ?? 0.0)
        self.humidity.currentRelativeHumidity.value = advertisement.humidity + (configuration?.calibration?.humidity ?? 0.0)
    }
}

// MARK: - EveHistoryAccessory

extension GoveeThermometerAccessory: EveHistoryAccessory {
    
    /// Time between history downloads.
    static var syncInterval: TimeInterval { 30 * 60 }
    
    /// Longest history requested in one download.
    static var maxHistoryMinutes: TimeInterval { 24 * 60 }
    
    var needsSync: Bool {
        if let lastSyncFailure, Date().timeIntervalSince(lastSyncFailure) < Self.syncRetryInterval {
            return false
        }
        return lastSync.map { Date().timeIntervalSince($0) >= Self.syncInterval } ?? true
    }
    
    /// Connects to the thermometer, reads its firmware version and downloads the readings since the last stored entry.
    ///
    /// - Returns: The number of history entries added.
    @discardableResult
    func sync(central: NativeCentral) async throws -> Int {
        do {
            let count = try await download(central: central)
            lastSync = Date()
            lastSyncFailure = nil
            return count
        }
        catch {
            lastSyncFailure = Date()
            throw error
        }
    }
    
    private func download(central: NativeCentral) async throws -> Int {
        let connection = try await central.connect(
            to: peripheral,
            model: model,
            connectTimeout: Self.syncConnectTimeout,
            timeout: Self.syncTimeout
        )
        let count: Int
        do {
            count = try await sync(connection: connection)
        }
        catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
        return count
    }
    
    private func sync(connection: GoveeConnection<NativeCentral>) async throws -> Int {
        self.lastSeen = Date()
        self.reachable = true
        if info.firmwareRevision?.value == Self.defaultFirmwareRevision,
           let version = try await connection.send(GoveeQuery.thermometerFirmwareVersion, timeout: Self.syncTimeout).thermometerFirmwareVersion {
            info.firmwareRevision?.value = version
        }
        // download minutes since the last entry
        let now = Date()
        // the H5072 disconnects partway through long downloads (after about 600 frames, 2.5 days)
        let maxMinutes = Self.maxHistoryMinutes
        let minutes = history.history.lastDate.map { (now.timeIntervalSince($0) / 60).rounded(.up) } ?? maxMinutes
        guard minutes >= EveHistory.interval / 60 else {
            return 0
        }
        let readings = try await connection.thermometerHistory(minutes: UInt16(min(minutes, maxMinutes)), timeout: Self.syncTimeout)
        let samples = readings.map {
            EveHistory.Sample(
                date: now - TimeInterval($0.minutesAgo) * 60,
                temperature: $0.temperature + (configuration?.calibration?.temperature ?? 0.0),
                humidity: $0.humidity + (configuration?.calibration?.humidity ?? 0.0)
            )
        }
        return history.history.append(averaging: samples, now: now)
    }
}

extension GoveeThermometerAccessory {
    
    /// Firmware revision shown until the thermometer reports its own.
    static var defaultFirmwareRevision: String { "1.0.0" }
}

extension GoveeThermometerAccessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let batteryLevel = PredefinedCharacteristic.batteryLevel(100)
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(batteryLevel),
                AnyCharacteristic(chargingState)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notChargeable
        }
    }
}

extension GoveeAccessory.Thermometer: SensorAdvertisement {
    
    public static var sensorType: String { "com.Govee.Thermometer" }
}
