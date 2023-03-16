//
//  ThermometerAccessory.swift
//  
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
import Bluetooth
import GATT
import CoreSensor

protocol SensorAccessory: AnyObject {
    
    associatedtype Advertisement: SensorAdvertisement
    
    var peripheral: NativeCentral.Peripheral { get }
    
    init(peripheral: NativeCentral.Peripheral, advertisement: Advertisement)
    
    func update(advertisement: Advertisement)
}
