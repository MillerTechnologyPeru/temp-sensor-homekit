//
//  CoreBluetooth.swift
//
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

#if canImport(CoreBluetooth)
import Foundation
import CoreBluetooth
import Bluetooth
import GATT
import DarwinGATT

internal protocol CoreBluetoothManager {
    
    var state: DarwinBluetoothState { get async }
}

extension DarwinPeripheral: CoreBluetoothManager { }
extension DarwinCentral: CoreBluetoothManager { }

extension CoreBluetoothManager {
    
    /// Wait for CoreBluetooth to be ready.
    func waitPowerOn(warning: Int = 3, timeout: Int = 10) async throws {
        
        var powerOnWait = 0
        while await state != .poweredOn {
            
            // inform user after 3 seconds
            if powerOnWait == warning {
                print("Waiting for CoreBluetooth to be ready, please turn on Bluetooth")
            }
            
            try await Task.sleep(timeInterval: 1.0)
            powerOnWait += 1
            guard powerOnWait < timeout
                else { throw TempSensorHomeKitToolError.bluetoothUnavailable }
        }
    }
}
#endif
