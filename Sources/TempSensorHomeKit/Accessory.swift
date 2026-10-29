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

@MainActor
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

/// Sensor accessory that exposes its readings to the Eve app as history.
protocol EveHistoryAccessory: SensorAccessory {
    
    /// Key for the history in persistent storage.
    var historyIdentifier: String { get }
    
    var history: EveHistoryService { get }
    
    /// Whether it is time to download the sensor's history again.
    var needsSync: Bool { get }
    
    /// Connects to the sensor and adds its stored readings to the history.
    ///
    /// - Returns: The number of history entries added.
    func sync(central: NativeCentral) async throws -> Int
}

extension EveHistoryAccessory {
    
    /// Time to wait before trying again after a failed history download.
    static var syncRetryInterval: TimeInterval { 5 * 60 }
    
    /// Time allowed to establish the Bluetooth connection for a history download.
    ///
    /// A connection attempt that times out stays queued for the peripheral, so keep this generous.
    static var syncConnectTimeout: TimeInterval { 30 }
    
    /// Time allowed for each reply, and between history records, during a download.
    static var syncTimeout: TimeInterval { 10 }
}
