//
//  Accessory.swift
//  
//
//  Created by Alsey Coleman Miller on 3/2/23.
//

import Foundation
import Bluetooth
import GATT
import HAP
import CoreSensor

final class GEThermometerAccessory: HAP.Accessory.Thermometer, SensorAccessory {
    
    let peripheral: NativeCentral.Peripheral
    
    private(set) var lastSeen: Date = Date()
    
    let configuration: SensorConfiguration.Sensor?
    
    //let bridgeState = Service.BridgingState()
    
    let humidity = HAP.Service.HumiditySensor()
    
    let battery = BatteryService()
    
    init(peripheral: NativeCentral.Peripheral, advertisement: GESensor, configuration: SensorConfiguration.Sensor?) {
        self.peripheral = peripheral
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "GE Thermometer Sensor",
            serialNumber: peripheral.description,
            manufacturer: "GE",
            model: configuration?.model ?? advertisement.model.description,
            firmwareRevision: "\(advertisement.version)"
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
    
    func update(advertisement: GESensor) {
        self.lastSeen = Date()
        self.reachable = true
        self.battery.batteryVoltage.value = advertisement.batteryVoltage
        self.battery.batteryLevel?.value = UInt8(advertisement.batteryLevel.rounded())
        self.battery.statusLowBattery.value = advertisement.batteryLevel < 25 ? .batteryLow : .batteryNormal
        self.temperatureSensor.currentTemperature.value = advertisement.temperatureCelcius + (configuration?.calibration?.temperature ?? 0.0)
        self.humidity.currentRelativeHumidity.value = advertisement.humidityPercentage + (configuration?.calibration?.humidity ?? 0.0)
    }
}

extension GEThermometerAccessory {
    
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
