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

final class SensorBridgeAccessory: HAP.Accessory {
    
    init(info: HAP.Service.Info) {
        super.init(
            info: info,
            type: .bridge,
            services: [
                
            ]
        )
    }
}
