//
//  SensorConfiguration.swift
//  
//
//  Created by Alsey Coleman Miller on 3/17/23.
//

import Foundation

public struct SensorConfiguration: Equatable, Hashable, Codable {
    
    public var sensors: [Sensor]
    
    public var timeout: UInt
    
    public var serialNumber: String
    
    public var model: String
    
    public var manufacturer: String
}

public extension SensorConfiguration {
    
    struct Sensor: Equatable, Hashable, Codable {
        
        /// Unique identifier for the sensor. Can be name or Bluetooth address.
        public let id: String
        
        public var calibration: Calibration?
    }
}

public extension SensorConfiguration {
    
    struct Calibration: Equatable, Hashable, Codable {
        
        /// Temperature delta
        public var temperature: Float?
        
        /// Humidity delta
        public var humidity: Float?
    }
}
