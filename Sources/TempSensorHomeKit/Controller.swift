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
import Govee
import Inkbird

final class SensorBridgeController {
    
    // MARK: - Properties
    
    var log: ((String) -> ())?
        
    private let hapDevice: HAP.Device
    
    private let server: HAP.Server
    
    private let central: NativeCentral
    
    private var accessories = [NativeCentral.Peripheral: HAP.Accessory]()
    
    // MARK: - Initialization
    
    public init(
        fileName: String,
        setupCode: HAP.Device.SetupCode,
        port: UInt,
        central: NativeCentral,
        serialNumber: String
    ) throws {
        
        // start server
        let info = Service.Info(
            name: "Sensor Bridge",
            serialNumber: serialNumber,
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
    
    @MainActor
    func scan() async throws {
        let stream = try await central.scan()
        for try await scanData in stream {
            if bridge(GEThermometerAccessory.self, from: scanData) {
                continue
            } else if bridge(GoveeThermometerAccessory.self, from: scanData) {
                continue
            } else if bridge(InkbirdThermometerAccessory.self, from: scanData) {
                continue
            } else {
                continue
            }
        }
    }
    
    @discardableResult
    private func bridge<T>(
        _ accessoryType: T.Type,
        from scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>
    ) -> Bool where T: SensorAccessory, T: HAP.Accessory {
        guard let sensorAdvertisement = T.Advertisement.init(scanData.advertisementData) else {
            return false
        }
        if let accessory = self.accessories[scanData.peripheral] as? T {
            accessory.update(advertisement: sensorAdvertisement)
        } else {
            let newAccessory = T.init(peripheral: scanData.peripheral, advertisement: sensorAdvertisement)
            self.accessories[scanData.peripheral] = newAccessory
            self.hapDevice.addAccessories([newAccessory])
            log?("Found \(T.Advertisement.sensorType) \(scanData.peripheral.description)")
        }
        return true
    }
}

// MARK: - HAP Device Delegate

extension SensorBridgeController: HAP.DeviceDelegate {
    
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
