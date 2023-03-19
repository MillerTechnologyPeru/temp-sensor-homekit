//
//  Storage.swift
//  
//
//  Created by Alsey Coleman Miller on 3/19/23.
//

import Foundation
import CoreSensor
import HAP

public struct Configuration: Equatable, Hashable, Codable {
        
    public var serialNumber: String
    
    public var model: String
    
    public var manufacturer: String
    
    public var sensors: [SensorConfiguration.Sensor]
    
    public var timeout: UInt
    
    internal var homeKit: String?
}

final class ConfigurationHAPStorage: Storage {
    
    private let encoder = JSONEncoder()
    
    private let decoder = JSONDecoder()
    
    private let fileManager = FileManager()
    
    let filename: String
    
    init(filename: String) {
        self.filename = filename
    }
    
    func readConfiguration() throws -> Configuration {
        let url = URL(fileURLWithPath: filename)
        let jsonData = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try decoder.decode(Configuration.self, from: jsonData)
    }
    
    func read() throws -> Data {
        let configuration = try readConfiguration()
        return configuration.homeKit?.data(using: .utf8) ?? Data()
    }
    
    func writeConfiguration(_ newValue: Configuration) throws {
        let jsonData = try encoder.encode(newValue)
        if fileManager.fileExists(atPath: filename) {
            try jsonData.write(to: URL(fileURLWithPath: filename), options: [.atomic])
        } else {
            fileManager.createFile(atPath: filename, contents: jsonData)
        }
    }
    
    func write(_ data: Data) throws {
        var configuration: Configuration
        if fileManager.fileExists(atPath: filename) {
            configuration = try readConfiguration()
        } else {
            configuration = Configuration(
                serialNumber: UUID().uuidString,
                model: UUID().uuidString,
                manufacturer: UUID().uuidString,
                sensors: [],
                timeout: 60 * 5,
                homeKit: nil
            )
        }
        configuration.homeKit = String(data: data, encoding: .utf8)
        try writeConfiguration(configuration)
    }
}
