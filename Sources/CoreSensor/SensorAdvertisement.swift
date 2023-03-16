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
    
    init?<T: AdvertisementData>(_ advertisement: T)
}
