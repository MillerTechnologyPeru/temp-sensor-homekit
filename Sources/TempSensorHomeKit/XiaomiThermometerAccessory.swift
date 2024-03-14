//
//  XiaomiThermometerAccessory.swift
//
//
//  Created by Alsey Coleman Miller on 3/14/24.
//

import Foundation
import Bluetooth
import BluetoothGATT
import GATT
import HAP
import CoreSensor
import XiaomiBluetooth

final class XiaomiThermometerAccessory: HAP.Accessory.Thermometer, SensorAccessory {
    
    let peripheral: NativeCentral.Peripheral
    
    private(set) var lastSeen: Date = Date()
    
    let configuration: SensorConfiguration.Sensor?
    
    //let bridgeState = Service.BridgingState()
    
    let humidity = HAP.Service.HumiditySensor()
    
    let battery = BatteryService()
    
    init(
        peripheral: NativeCentral.Peripheral,
        advertisement: MiBeacon,
        configuration: SensorConfiguration.Sensor?
    ) {
        self.peripheral = peripheral
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "Xiaomi Thermometer Sensor",
            serialNumber: advertisement.address?.rawValue ?? peripheral.description,
            manufacturer: "Xiaomi",
            model: configuration?.model ?? advertisement.product.description,
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                //bridgeState,
                humidity,
                battery
            ]
        )
        //self.bridgeState.accessoryIdentifier.value = peripheral.description
        self.update(advertisement: advertisement)
    }
    
    func update(advertisement: MiBeacon) {
        self.lastSeen = Date()
        self.reachable = true
        self.temperatureSensor.currentTemperature.value = 20.0
        self.humidity.currentRelativeHumidity.value = 45.0
    }
}

// MARK: - ConnectableSensorAccessory

extension XiaomiThermometerAccessory: ConnectableSensorAccessory {
    
    // Connect and update values
    func update(connection: GATTConnection<NativeCentral>) async throws {
        self.lastSeen = Date()
        self.reachable = true
        // search for characteristic
        guard let temperatureCharacteristic = connection.cache.characteristic(TemperatureHumidityCharacteristic.uuid, service: TemperatureHumidityCharacteristic.service) else {
            throw TempSensorHomeKitToolError.characteristicNotFound(TemperatureHumidityCharacteristic.uuid)
        }
        // read and parse data
        let data = try await connection.central.readValue(for: temperatureCharacteristic)
        guard let temperatureCharacteristicValue = TemperatureHumidityCharacteristic(data: data) else {
            throw TempSensorHomeKitToolError.invalidCharacteristicValue(TemperatureHumidityCharacteristic.uuid)
        }
        // update temperature and humidity values
        update(characteristic: temperatureCharacteristicValue)
        
        // read battery level
        if let characteristic = connection.cache.characteristic(.batteryLevel, service: .batteryService) {
            let data = try await connection.central.readValue(for: characteristic)
            guard let value = BluetoothGATT.GATTBatteryLevel(data: data) else {
                throw TempSensorHomeKitToolError.invalidCharacteristicValue(.batteryLevel)
            }
            update(characteristic: value)
        }
        
        // read information
        if let characteristic = connection.cache.characteristic(.firmwareRevisionString, service: .deviceInformation) {
            let data = try await connection.central.readValue(for: characteristic)
            guard let value = GATTFirmwareRevisionString(data: data) else {
                throw TempSensorHomeKitToolError.invalidCharacteristicValue(.firmwareRevisionString)
            }
            update(characteristic: value)
        }
    }
}

private extension XiaomiThermometerAccessory {
    
    func update(characteristic: TemperatureHumidityCharacteristic) {
        // battery voltage
        self.battery.batteryVoltage.value = Float(characteristic.batteryVoltage.voltage)
        // temperature
        self.temperatureSensor.currentTemperature.value = characteristic.temperature.celcius + (configuration?.calibration?.temperature ?? 0.0)
        // humidity
        self.humidity.currentRelativeHumidity.value = Float(characteristic.humidity.rawValue) + (configuration?.calibration?.humidity ?? 0.0)
    }
    
    func update(characteristic: BluetoothGATT.GATTBatteryLevel) {
        self.battery.batteryLevel?.value = characteristic.level.rawValue
    }
    
    func update(characteristic: BluetoothGATT.GATTFirmwareRevisionString) {
        self.info.firmwareRevision?.value = characteristic.rawValue
    }
}

// MARK: - Battery Service

extension XiaomiThermometerAccessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        let batteryVoltage = GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "5C7D8287-D288-4F4D-BB4A-161A83A99752")!),
            value: 3.3,
            permissions: [.read, .events],
            description: "Battery Voltage",
            format: .float,
            unit: .none
        )
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let batteryLevel = PredefinedCharacteristic.batteryLevel(100)
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(batteryLevel),
                AnyCharacteristic(chargingState),
                AnyCharacteristic(batteryVoltage)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notChargeable
        }
    }
}

// MARK: - Advertisement

extension MiBeacon: SensorAdvertisement {
    
    public static var sensorType: String { "com.Xiaomi.Thermometer" }
}
