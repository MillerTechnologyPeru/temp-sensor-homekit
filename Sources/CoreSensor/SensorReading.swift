//
//  SensorReading.swift
//  
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

/// Sensor values
public enum SensorReading: Equatable, Hashable, Codable {
    
    case temperature(Float)
    case humidity(Float)
    case batteryLevel(Float)
}
