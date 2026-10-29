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
}
