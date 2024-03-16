//
//  GoveeThermometerAccessory.swift
//  
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
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
    
    init(peripheral: NativeCentral.Peripheral, advertisement: GoveeAccessory.Thermometer, configuration: SensorConfiguration.Sensor?) {
        self.peripheral = peripheral
        self.configuration = configuration
        let id = advertisement.id.rawValue
        let info = Service.Info.Info(
            name: configuration?.name ?? "Govee Thermometer Sensor",
            serialNumber: id,
            manufacturer: "Shenzhen Intellirocks Tech. Co., Ltd.",
            model: configuration?.model ?? advertisement.id.model.rawValue,
            firmwareRevision: "1.0.0"
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
                battery
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
