//
//  InkbirdThermometerAccessory.swift
//  
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
import Bluetooth
import GATT
import HAP
import Inkbird
import CoreSensor

final class InkbirdThermometerAccessory: HAP.Accessory.Thermometer, SensorAccessory {
    
    let peripheral: NativeCentral.Peripheral
    
    private(set) var lastSeen: Date = Date()
    
    let configuration: SensorConfiguration.Sensor?
    
    //let bridgeState = Service.BridgingState()
    
    let humidity = HAP.Service.HumiditySensor()
    
    let battery = BatteryService()
    
    let history = EveHistoryService()
    
    /// Last time the history was downloaded.
    private(set) var lastSync: Date?
    
    /// Last time a history download failed.
    private(set) var lastSyncFailure: Date?
    
    var historyIdentifier: String {
        peripheral.description
    }
    
    init(peripheral: NativeCentral.Peripheral, advertisement: InkbirdAdvertisement.Thermometer, configuration: SensorConfiguration.Sensor?) {
        self.peripheral = peripheral
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "Inkbird Thermometer Sensor",
            serialNumber: peripheral.description,
            manufacturer: "Inkbird",
            model: configuration?.model ?? advertisement.name.rawValue,
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                //bridgeState,
                humidity,
                battery,
                history
            ]
        )
        //self.bridgeState.accessoryIdentifier.value = peripheral.description
        self.update(advertisement: advertisement)
    }
    
    func update(advertisement: InkbirdAdvertisement.Thermometer) {
        self.lastSeen = Date()
        self.reachable = true
        self.battery.batteryLevel?.value = advertisement.manufacturingData.batteryLevel.rawValue
        self.battery.statusLowBattery.value = advertisement.manufacturingData.batteryLevel.rawValue < 25 ? .batteryLow : .batteryNormal
        self.temperatureSensor.currentTemperature.value = advertisement.manufacturingData.temperature.celcius + (configuration?.calibration?.temperature ?? 0.0)
        self.humidity.currentRelativeHumidity.value = advertisement.manufacturingData.humidity.percentage + (configuration?.calibration?.humidity ?? 0.0)
    }
}

// MARK: - EveHistoryAccessory

extension InkbirdThermometerAccessory: EveHistoryAccessory {
    
    /// Time between history downloads. Each download reads the whole buffer, about 90 seconds.
    static var syncInterval: TimeInterval { 60 * 60 }
    
    var needsSync: Bool {
        if let lastSyncFailure, Date().timeIntervalSince(lastSyncFailure) < Self.syncRetryInterval {
            return false
        }
        return lastSync.map { Date().timeIntervalSince($0) >= Self.syncInterval } ?? true
    }
    
    /// Connects to the sensor and downloads its stored history, adding the readings newer than the last stored entry.
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
        let connection = try await central.connect(to: peripheral, model: .ibsTH2)
        let readings: [InkbirdHistoryReading]
        do {
            readings = try await connection.history()
        }
        catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
        self.lastSeen = Date()
        self.reachable = true
        let samples = readings.map {
            EveHistory.Sample(
                date: $0.date,
                temperature: $0.temperature + (configuration?.calibration?.temperature ?? 0.0),
                humidity: $0.humidity + (configuration?.calibration?.humidity ?? 0.0)
            )
        }
        return history.history.append(averaging: samples)
    }
}

extension InkbirdThermometerAccessory {
    
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

extension InkbirdAdvertisement.Thermometer: SensorAdvertisement {
    
    public static var sensorType: String { "com.Inkbird.Thermometer" }
}
