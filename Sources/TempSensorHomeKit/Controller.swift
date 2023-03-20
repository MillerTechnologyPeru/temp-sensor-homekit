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

@MainActor
final class SensorBridgeController {
    
    // MARK: - Properties
    
    var log: ((String) -> ())?
        
    private let hapDevice: HAP.Device
    
    private let server: HAP.Server
    
    private let central: NativeCentral
    
    private let battery: BatterySource?
    
    let configuration: SensorConfiguration
    
    private var accessories = [NativeCentral.Peripheral: HAP.Accessory]()
    
    // MARK: - Initialization
    
    public init(
        fileName: String,
        setupCode: HAP.Device.SetupCode,
        port: UInt,
        central: NativeCentral,
        battery: BatterySource? = nil
    ) throws {
        // start server
        let storage = ConfigurationHAPStorage(filename: fileName)
        let configuration: SensorConfiguration = (try? storage.readConfiguration()).flatMap({ .init($0) }) ?? SensorConfiguration()
        let info = Service.Info(
            name: configuration.name,
            serialNumber: configuration.serialNumber,
            model: configuration.model,
            firmwareRevision: TempSensorHomeKitTool.configuration.version
        )
        var services = [HAP.Service]()
        if let battery = battery {
            services.append(BridgeBatteryService(source: battery))
        }
        let hapDevice = HAP.Device(
            bridgeInfo: info,
            setupCode: setupCode,
            storage: storage,
            services: services
        )
        self.hapDevice = hapDevice
        self.central = central
        self.configuration = configuration
        self.battery = battery
        self.server = try HAP.Server(device: hapDevice, listenPort: Int(port))
        self.hapDevice.delegate = self
    }
    
    // MARK: - Methods
    
    func scan() async throws {
        Task {
            try await reachabilityWatchdog()
        }
        #if os(Linux)
        let stream = try await central.scan(
            filterDuplicates: false,
            parameters: HCILESetScanParameters(
                type: .active,
                interval:  .max,
                window: .max,
                addressType: .public,
                filterPolicy: .accept
            )
        )
        #else
        let stream = try await central.scan(
            filterDuplicates: false
        )
        #endif
        for try await scanData in stream {
            if bridge(GEThermometerAccessory.self, from: scanData) {
                continue
            } else if bridge(GoveeThermometerAccessory.self, from: scanData) {
                continue
            } else if bridge(InkbirdThermometerAccessory.self, from: scanData) {
                continue
            } else if (scanData.advertisementData.localName ?? "").hasPrefix("GVH") {
                log?("Unable to parse Govee \(scanData.advertisementData.localName ?? "")")
                #if DEBUG
                if let additionalData = scanData.advertisementData.manufacturerData?.additionalData {
                    log?("Invalid Govee manufacturer data: \([UInt8](additionalData))")
                }
                #endif
                continue
            } else if let manufacturerData = scanData.advertisementData.manufacturerData, 
                manufacturerData.companyIdentifier == GESensor.companyIdentifier {
                log?("Unable to parse GE \(manufacturerData)")
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
        guard filter(scanData) else {
            log?("Ignoring \(T.Advertisement.sensorType) \(scanData.peripheral.description)")
            return false
        }
        if let accessory = self.accessories[scanData.peripheral] as? T {
            accessory.update(advertisement: sensorAdvertisement)
        } else {
            let newAccessory = T.init(peripheral: scanData.peripheral, advertisement: sensorAdvertisement, configuration: configuration(for: scanData))
            self.accessories[scanData.peripheral] = newAccessory
            self.hapDevice.addAccessories([newAccessory])
            log?("Found \(T.Advertisement.sensorType) \(scanData.peripheral.description)")
        }
        return true
    }
    
    private func filter(_ scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>) -> Bool {
        // filtering disabled
        guard configuration.sensors.isEmpty == false else {
            return true
        }
        return configuration(for: scanData) != nil
    }
    
    private func configuration(for scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>) -> SensorConfiguration.Sensor? {
        return configuration.sensors
            .first(where: { $0.id == scanData.peripheral.description || $0.id == scanData.advertisementData.localName })
    }
    
    private func reachabilityWatchdog() async throws {
        let timeout = TimeInterval(self.configuration.timeout)
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            for (peripheral, accessory) in accessories {
                let lastSeen = (accessory as? any SensorAccessory)!.lastSeen
                if Date().timeIntervalSince(lastSeen) > timeout {
                    self.accessories[peripheral] = nil // Remove accessory
                    self.hapDevice.removeAccessories([accessory])
                    log?("Removed unreachable \(peripheral)")
                }
            }
        }
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

internal extension HAP.Device {
    
    /// A bridge is a special type of HAP accessory server that bridges HomeKit
    /// Accessory Protocol and different RF/transport protocols, such as ZigBee
    /// or Z-Wave. A bridge must expose all the user-addressable functionality
    /// supported by its connected devices as HAP accessory objects to the HAP
    /// controller(s). A bridge must ensure that the instance ID assigned to the
    /// HAP accessory objects exposed on behalf of its connected devices do not
    /// change for the lifetime of the server/client pairing.
    ///
    /// For example, a bridge that bridges three lights would expose four HAP
    /// accessory objects: one HAP accessory object that represents the bridge
    /// itself that may include a "firmware update" service, and three
    /// additional HAP accessory objects that each contain a "lightbulb"
    /// service.
    ///
    /// A bridge must not expose more than 100 HAP accessory objects.
    ///
    /// Any accessories, regardless of transport, that enable physical access to
    /// the home, such as door locks, must not be bridged. Accessories that
    /// support IP transports, such as Wi-Fi, must not be bridged. Accessories
    /// that support Bluetooth LE that can be controlled, such as a light bulb,
    /// must not be bridged. Accessories that support Bluetooth LE that only
    /// provide data, such as a temperature sensor, and accessories that support
    /// other transports, such as a ZigBee light bulb or a proprietary RF
    /// sensor, may be bridged.
    ///
    /// - Parameters:
    ///   - bridgeInfo: information about the bridge
    ///   - setupCode: the code to pair this device, must be in the format XXX-XX-XXX
    ///   - storage: persistence interface for storing pairings, secrets
    ///   - accessories: accessories to be bridged
    convenience init(
        bridgeInfo: HAP.Service.Info,
        setupCode: SetupCode = .random,
        storage: Storage,
        services: [HAP.Service]
    ) {
        let bridge = Accessory(info: bridgeInfo, type: .bridge, services: services)
        self.init(setupCode: setupCode, storage: storage, accessory: bridge)
    }
}
