//
//  GESensor.swift
//  
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

import Foundation
import Bluetooth
import GATT

/// GE Temp Sensor
public struct GESensor: Equatable, Hashable, Codable {
    
    /// Model identifier
    public let model: UInt8
    
    /// Protocol Version
    public let version: UInt8
    
    /// Battery Level
    public let battery: UInt8
    
    /// Temperature
    public let temperature: UInt16
    
    /// Humidity
    public let humidity: UInt16
    
    /// Checksum
    public let checksum: UInt32
}

extension GESensor: SensorAdvertisement {
    
    public static var sensorType: String { "com.ge.sensor" }
    
    public init?<T: AdvertisementData>(advertisement: T) {
        guard let manufacturerData = advertisement.manufacturerData else {
            return nil
        }
        self.init(manufacturerData: manufacturerData)
    }
    
    public init?(manufacturerData: GATT.ManufacturerSpecificData) {
        
        guard manufacturerData.companyIdentifier == Self.companyIdentifier,
            manufacturerData.additionalData.count == 18
            else { return nil }
        
        let data = manufacturerData.additionalData
        self.model = data[0]
        self.version = data[1]
        self.battery = data[2]
        self.temperature = UInt16(bigEndian: UInt16(bytes: (data[3], data[4])))
        self.humidity = UInt16(bigEndian: UInt16(bytes: (data[5], data[6])))
        self.checksum = UInt32(bigEndian: UInt32(bytes: (data[14], data[15], data[16], data[17])))
    }
}

public extension GESensor {
    
    static var companyIdentifier: Bluetooth.CompanyIdentifier { 473 }
}

public extension GESensor {
    
    var batteryVoltage: Float {
        1.0 + (Float(battery) / 100)
    }
    
    var batteryLevel: Float {
        (min(batteryVoltage, 3.3) / 3.3) * 100
    }
    
    var temperatureCelcius: Float {
        min(Float(temperature) / 10, 100.0)
    }
    
    var humidityPercentage: Float {
        max(min(Float(humidity) / 10, 100.0), 0)
    }
}

public extension GESensor {
    
    func read<Central: CentralManager>(peripheral: Central.Peripheral, central: Central) -> [SensorReading] {
        read()
    }
    
    func read() -> [SensorReading] {
        return [
            .batteryLevel(batteryLevel),
            .temperature(temperatureCelcius),
            .humidity(humidityPercentage)
        ]
    }
}
