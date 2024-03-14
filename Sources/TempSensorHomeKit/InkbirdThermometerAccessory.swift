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
                battery
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

extension InkbirdThermometerAccessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let batteryLevel = PredefinedCharacteristic.batteryLevel()
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
