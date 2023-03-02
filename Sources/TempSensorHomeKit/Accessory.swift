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

final class GESensorAccessory: HAP.Accessory.Thermometer {
    
    let peripheral: NativeCentral.Peripheral
    
    init(peripheral: NativeCentral.Peripheral, advertisement: GESensor) {
        self.peripheral = peripheral
        let info = Service.Info.Info(
            name: "GE Sensor",
            serialNumber: peripheral.description,
            manufacturer: "GE",
            model: "\(advertisement.model)",
            firmwareRevision: "\(advertisement.version)"
        )
        super.init(
            info: info,
            additionalServices: []
        )
        update(advertisement: advertisement)
    }
    
    func update(advertisement: GESensor) {
        self.reachable = true
        self.temperatureSensor.currentTemperature.value = advertisement.temperatureCelcius
    }
}
