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
    
    internal var homeKit: HomeKit?
}

public extension SensorConfiguration {
    
    init(_ configuration: Configuration) {
        self.init(
            sensors: configuration.sensors,
            timeout: configuration.timeout,
            serialNumber: configuration.serialNumber,
            model: configuration.model,
            manufacturer: configuration.manufacturer
        )
    }
}

public extension Configuration {
    
    struct HomeKit: Equatable, Hashable, Codable {
        
        public let identifier: String
        
        public var setupCode: String
        
        public var setupKey: String
        
        public var stableHash: Int
        
        public var privateKey: Data
        
        public var number: UInt32
        
        public var aidForAccessorySerialNumber = [String: InstanceID]()
        
        public var aidGenerator = AIDGenerator()
        
        public var pairings: [PairingIdentifier: Pairing] = [:]
    }
}

public extension Configuration.HomeKit {
    
    typealias InstanceID = Int
    
    typealias PairingIdentifier = Data
    
    typealias PublicKey = Data
    
    struct Pairing: Codable, Equatable, Hashable {
        
        public enum Role: UInt8, Codable {
            case regularUser = 0x00
            case admin = 0x01
        }

        // iOS Device's Pairing Identifier, iOSDevicePairingID
        public let identifier: PairingIdentifier

        // iOS Device's Curve25519 public key
        public let publicKey: PublicKey

        public var role: Role
    }
    
    struct AIDGenerator: Codable, Equatable, Hashable {
        public var lastAID: InstanceID = 1
    }
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
        guard let homeKit = configuration.homeKit else {
            throw CocoaError(.coderValueNotFound)
        }
        return try encoder.encode(homeKit)
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
        configuration.homeKit = try decoder.decode(Configuration.HomeKit.self, from: data)
        try writeConfiguration(configuration)
    }
}
