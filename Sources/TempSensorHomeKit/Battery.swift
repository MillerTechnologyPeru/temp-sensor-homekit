//
//  Battery.swift
//  
//
//  Created by Alsey Coleman Miller on 3/19/23.
//

import Foundation
import HAP
#if os(macOS)
import IOKit.ps
#endif

public protocol BatterySource {
    
    func read() throws -> UInt
}

#if os(macOS)

public final class MacBattery: BatterySource {
    
    public let name: String?
    
    public init(name: String) {
        self.name = name
    }
    
    public init?() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        guard sources.isEmpty == false else {
            return nil
        }
        self.name = nil
    }
    
    public func read() throws -> UInt {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for ps in sources {
            let info = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as! [String: AnyObject]
            if let powerSourceName = info[kIOPSNameKey] as? String,
                let capacity = info[kIOPSCurrentCapacityKey] as? Int {
                if let name = self.name, powerSourceName != name {
                    continue
                }
                return UInt(capacity)
            }
            continue
        }
        throw CocoaError(.featureUnsupported)
    }
}

#elseif os(Linux)

public final class LinuxBattery: BatterySource {
    
    let filePath: String
    
    init(filePath: String) {
        self.path = path
    }
    
    func read() throws -> UInt {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: [.mappedIfSafe])
        guard let string = String(data: data, encoding: .utf8), let value = UInt(string) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
}

#endif

final class BridgeBatteryService: HAP.Service.Battery {
    
    let source: BatterySource
    
    private var timer: Timer!
    
    init(source: BatterySource) {
        self.source = source
        let name = PredefinedCharacteristic.name("Battery")
        let batteryLevel = PredefinedCharacteristic.batteryLevel()
        batteryLevel.value = 100
        //let chargingState = PredefinedCharacteristic.chargingState()
        super.init(characteristics: [
            AnyCharacteristic(name),
            AnyCharacteristic(batteryLevel),
            //AnyCharacteristic(chargingState)
        ])
        self.statusLowBattery.value = .batteryNormal
        //self.chargingState?.value = .notChargeable
        try? update()
        self.timer = .scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            do {
                try self.update()
            }
            catch {
                assertionFailure("Unable to update battery level: \(error)")
            }
        }
    }
    
    func update() throws {
        let batteryLevel = try source.read()
        self.batteryLevel?.value = UInt8(batteryLevel)
        self.statusLowBattery.value = batteryLevel > 15 ? .batteryNormal : .batteryLow
    }
}
