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
import TPMS
import XiaomiBluetooth

@MainActor
final class SensorBridgeController {
    
    // MARK: - Properties
    
    var log: ((String) -> ())? {
        didSet { scanner.log = log }
    }
        
    private let hapDevice: HAP.Device
    
    private let server: HAP.Server
    
    private let battery: BatterySource?
    
    let configuration: SensorConfiguration
    
    private let store: SensorStore
    
    private let scanner: SensorScanner
    
    private var accessories = [Sensor.ID: SensorAccessory]()
    
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
        let store = try SensorStore(configurationFile: fileName, limit: configuration.historyLimit)
        self.hapDevice = hapDevice
        self.configuration = configuration
        self.battery = battery
        self.store = store
        self.scanner = SensorScanner(central: central, store: store, configuration: configuration)
        self.server = try HAP.Server(device: hapDevice, listenPort: Int(port))
        self.hapDevice.delegate = self
    }
    
    // MARK: - Methods
    
    /// Shows the stored sensors in HomeKit, then scans for sensors, updating HomeKit from the store.
    func scan() async throws {
        await loadSensors()
        Task {
            await observeChanges()
        }
        Task {
            await updateReachability()
        }
        try await scanner.run()
    }
}

// MARK: - HomeKit

private extension SensorBridgeController {
    
    /// Time between checks for sensors that stopped being found.
    static var reachabilityInterval: TimeInterval { 30 }
    
    var timeout: TimeInterval {
        TimeInterval(configuration.timeout)
    }
    
    /// Adds the stored sensors, with their last values.
    func loadSensors() async {
        do {
            for sensor in try await store.sensors() {
                await add(sensor)
            }
        }
        catch {
            log?("Unable to read sensors. \(error)")
        }
    }
    
    /// Updates the accessories as the scanner writes to the store.
    func observeChanges() async {
        for await change in store.changes {
            switch change {
            case let .sensor(sensor):
                if let accessory = accessories[sensor.id] {
                    accessory.update(sensor, timeout: timeout)
                } else {
                    await add(sensor)
                }
            case let .history(id, history):
                accessories[id]?.history.history = history
            }
        }
    }
    
    /// Shows sensors not found within the timeout as unreachable.
    func updateReachability() async {
        while true {
            try? await Task.sleep(timeInterval: Self.reachabilityInterval)
            do {
                for sensor in try await store.sensors() {
                    accessories[sensor.id]?.updateReachability(lastSeen: sensor.lastSeen, timeout: timeout)
                }
            }
            catch {
                log?("Unable to read sensors. \(error)")
            }
        }
    }
    
    func add(_ sensor: Sensor) async {
        guard accessories[sensor.id] == nil else {
            return
        }
        guard let kind = SensorKind(type: sensor.type) else {
            log?("Unknown sensor type \(sensor.type) of \(sensor.id)")
            return
        }
        let history: EveHistory
        do {
            history = try await store.history(for: sensor.id, fields: kind.historyFields)
        }
        catch {
            log?("Unable to read history of \(sensor.id). \(error)")
            history = EveHistory(fields: kind.historyFields)
        }
        // added while reading the history
        guard accessories[sensor.id] == nil else {
            return
        }
        let accessory = SensorAccessory(sensor: sensor, kind: kind, history: history)
        accessory.update(sensor, timeout: timeout)
        accessories[sensor.id] = accessory
        hapDevice.addAccessories([accessory])
        log?("Added \(sensor.id)")
    }
}

// MARK: - HAP Device Delegate

extension SensorBridgeController: @preconcurrency HAP.DeviceDelegate {
    
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
