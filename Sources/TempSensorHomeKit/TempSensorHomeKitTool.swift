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
struct TempSensorHomeKit {
    
    static func main() {
        
        // start async code
        Task {
            do {
                try await start()
            }
            catch {
                fatalError("\(error)")
            }
        }
        
        // run main loop
        RunLoop.current.run()
    }
    
    private static func start() async throws {
        
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
                type: .passive,
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
        
        // start scanning
        let stream = try await central.scan()
        for try await scanResult in stream {
            guard let sensor = GESensor(advertisement: scanResult.advertisementData) else {
                continue
            }
            dump(sensor)
        }
    }
}
