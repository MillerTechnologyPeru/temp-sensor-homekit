//
//  Controller.swift
//  
//
//  Created by Alsey Coleman Miller on 3/2/23.
//

import Foundation
import Bluetooth
import GATT
import HAP
import CoreSensor

final class SensorController {
    
    // MARK: - Properties
    
    var log: ((String) -> ())?
        
    private let hapDevice: HAP.Device
    
    private let server: HAP.Server
    
    private let central: NativeCentral
        
    // MARK: - Initialization
    
    public init(
        fileName: String,
        setupCode: HAP.Device.SetupCode,
        port: UInt,
        central: NativeCentral
    ) throws {
        
        // start server
        let info = Service.Info(
            name: "Sensor Bridge",
            serialNumber: "0000",
            firmwareRevision: TempSensorHomeKitTool.configuration.version
        )
        let storage = FileStorage(filename: fileName)
        let hapDevice = HAP.Device(
            bridgeInfo: info,
            setupCode: setupCode,
            storage: storage,
            accessories: []
        )
        self.hapDevice = hapDevice
        self.central = central
        self.server = try HAP.Server(device: hapDevice, listenPort: Int(port))
        self.hapDevice.delegate = self
    }
    
    // MARK: - Methods
    
    func scan() async throws {
        
    }
}

// MARK: - HAP Device Delegate

extension SensorController: HAP.DeviceDelegate {
    
    func didRequestIdentificationOf(_ accessory: Accessory) {
        log?("Requested identification of accessory \(String(describing: accessory.info.name.value ?? ""))")
    }

    func characteristic<T>(_ characteristic: HAP.GenericCharacteristic<T>,
                           ofService service: HAP.Service,
                           ofAccessory accessory: HAP.Accessory,
                           didChangeValue newValue: T?) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") did change: \(String(describing: newValue))")
        
    }

    func characteristicListenerDidSubscribe(_ accessory: HAP.Accessory,
                                            service: HAP.Service,
                                            characteristic: AnyCharacteristic) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") got a subscriber")
    }

    func characteristicListenerDidUnsubscribe(_ accessory: HAP.Accessory,
                                              service: HAP.Service,
                                              characteristic: AnyCharacteristic) {
        log?("Characteristic \(characteristic) in service \(service.type) of accessory \(accessory.info.name.value ?? "") lost a subscriber")
    }
    
    func didChangePairingState(from: PairingState, to: PairingState) {
        if to == .notPaired {
            printPairingInstructions()
        }
    }
    
    func printPairingInstructions() {
        if hapDevice.isPaired {
            log?("The device is paired, either unpair using your iPhone or remove the configuration file.")
        } else {
            log?("Scan the following QR code using your iPhone to pair this device:")
            log?(hapDevice.setupQRCode.asText)
        }
    }
}
