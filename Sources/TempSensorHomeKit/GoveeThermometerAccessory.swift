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
    
    //let bridgeState = Service.BridgingState()
    
    let humidity = HAP.Service.HumiditySensor()
    
    let battery = BatteryService()
    
    init(peripheral: NativeCentral.Peripheral, advertisement: GoveeAdvertisement.Thermometer) {
        self.peripheral = peripheral
        let info = Service.Info.Info(
            name: "Govee Thermometer Sensor",
            serialNumber: peripheral.description,
            manufacturer: "Govee (Shenzhen Intellirocks Tech. Co., Ltd.)",
            model: advertisement.name,
            firmwareRevision: ""
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
    
    func update(advertisement: GoveeAdvertisement.Thermometer) {
        self.reachable = true
        self.battery.batteryLevel?.value = advertisement.manufacturingData.batteryLevel
        self.battery.statusLowBattery.value = advertisement.manufacturingData.batteryLevel < 25 ? .batteryLow : .batteryNormal
        self.temperatureSensor.currentTemperature.value = advertisement.manufacturingData.temperature
        self.humidity.currentRelativeHumidity.value = advertisement.manufacturingData.humidity
    }
}

extension GoveeThermometerAccessory {
    
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

extension GoveeAdvertisement.Thermometer: SensorAdvertisement {
    
    public static var sensorType: String { "com.Govee.Thermometer" }
}
