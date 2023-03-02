//
//  SensorAdvertisement.swift
//  
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

import Foundation
import Bluetooth
import GATT

/// Sensor Advertisement protocol
public protocol SensorAdvertisement {
    
    static var sensorType: String { get }
    
    init?<T: AdvertisementData>(advertisement: T)
    
    func read<Central: CentralManager>(peripheral: Central.Peripheral, central: Central) async throws -> [SensorReading]
}
