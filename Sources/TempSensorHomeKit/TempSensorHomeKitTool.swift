#if os(Linux)
import Glibc
import BluetoothLinux
#elseif os(macOS)
import Darwin
import DarwinGATT
#endif

import Foundation
import CoreFoundation
import Dispatch

import Bluetooth
import GATT
import CoreSensor
import HAP
import ArgumentParser

#if os(Linux)
typealias LinuxCentral = GATTCentral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
typealias LinuxPeripheral = GATTPeripheral<BluetoothLinux.HostController, BluetoothLinux.L2CAPSocket>
typealias NativeCentral = LinuxCentral
typealias NativePeripheral = LinuxPeripheral
#elseif os(macOS)
typealias NativeCentral = DarwinCentral
typealias NativePeripheral = DarwinPeripheral
#else
#error("Unsupported platform")
#endif

@main
struct TempSensorHomeKitTool: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        abstract: "A deamon for exposing Bluetooth temperature sensors to HomeKit",
        version: "1.0.0"
    )
    
    @Option(help: "The name of the configuration file.")
    var file: String = "configuration.json"
    
    @Option(help: "The HomeKit setup code.")
    var setupCode: String?
    
    @Option(help: "The port of the HAP server.")
    var port: UInt = 8000
    
    private static var controller: SensorBridgeController!
    
    func run() throws {
        
        // start async code
        Task {
            do {
                let central = try await Self.loadBluetooth()
                let serialNumber: String
                #if os(Linux)
                let address = try await central.hostController.readDeviceAddress()
                serialNumber = address.rawValue
                #elseif os(macOS)
                serialNumber = Host.current().address ?? "1234"
                #endif
                try await MainActor.run {
                    let controller = try SensorBridgeController(
                        fileName: file,
                        setupCode: setupCode.map { .override($0) } ?? .random,
                        port: port,
                        central: central,
                        serialNumber: serialNumber
                    )
                    controller.log = { print($0) }
                    controller.printPairingInstructions()
                    Self.controller = controller
                }
                try await Self.controller.scan()
            }
            catch {
                fatalError("\(error)")
            }
        }
        
        // run main loop
        RunLoop.main.run()
    }
    
    private static func loadBluetooth() async throws -> NativeCentral {
        
        #if os(Linux)
        var hostController: HostController! = await HostController.default
                
        // keep trying to load Bluetooth device
        while hostController == nil {
            print("No Bluetooth adapters found")
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            hostController = await HostController.default
        }
                
        let address = try await hostController.readDeviceAddress()
        print("Bluetooth Address: \(address)")
        let clientOptions = GATTCentralOptions(
            maximumTransmissionUnit: .max,
            scanParameters: HCILESetScanParameters(
                type: .active,
                interval: .max,
                window: .max,
                addressType: .public,
                filterPolicy: .accept
            )
        )
        let central = LinuxCentral(
            hostController: hostController,
            options: clientOptions,
            socket: BluetoothLinux.L2CAPSocket.self
        )
        #elseif os(macOS)
        let central = DarwinCentral()
        #else
        #error("Invalid platform")
        #endif
        
        #if DEBUG
        central.log = { print("Central: \($0)") }
        #endif
        
        #if os(macOS)
        // wait until XPC connection to blued is established and hardware is on
        try await central.waitPowerOn()
        #endif
        
        return central
    }
}
