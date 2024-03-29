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
    
    var lastSeen: Date { get }
    
    init(peripheral: NativeCentral.Peripheral, advertisement: Advertisement, configuration: SensorConfiguration.Sensor?)
    
    func update(advertisement: Advertisement)
}

protocol ConnectableSensorAccessory: SensorAccessory {
    
    func update(connection: GATTConnection<NativeCentral>) async throws
}
