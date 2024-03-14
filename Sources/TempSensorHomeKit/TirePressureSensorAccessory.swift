//
//  TirePressureSensorAccessory.swift
//
//
//  Created by Alsey Coleman Miller on 3/14/24.
//

import Foundation
import Bluetooth
import GATT
import HAP
import TPMS
import CoreSensor

final class TirePressureSensorAccessory: HAP.Accessory.Thermometer, SensorAccessory {
    
    let peripheral: NativeCentral.Peripheral
    
    private(set) var lastSeen: Date = Date()
    
    let configuration: SensorConfiguration.Sensor?
    
    //let bridgeState = Service.BridgingState()
    
    let pressureSensor = TirePressureSensorService()
    
    let battery = BatteryService()
    
    init(peripheral: NativeCentral.Peripheral, advertisement: TirePressureSensor, configuration: SensorConfiguration.Sensor?) {
        self.peripheral = peripheral
        self.configuration = configuration
        let info = Service.Info.Info(
            name: configuration?.name ?? "Tire Pressure Monitoring System Sensor",
            serialNumber: advertisement.address.rawValue,
            manufacturer: "TPMS",
            model: configuration?.model ?? "TPMS",
            firmwareRevision: "1.0.0"
        )
        super.init(
            info: info,
            additionalServices: [
                //bridgeState,
                pressureSensor,
                battery
            ]
        )
        //self.bridgeState.accessoryIdentifier.value = peripheral.description
        self.update(advertisement: advertisement)
    }
    
    func update(advertisement: TirePressureSensor) {
        self.lastSeen = Date()
        self.reachable = true
        // tire pressure
        self.pressureSensor.currentPressure.value = Float(advertisement.pressure.poundPerSquareInch)
        // battery
        self.battery.batteryLevel?.value = advertisement.batteryLevel.rawValue
        self.battery.statusLowBattery.value = advertisement.batteryLevel.rawValue < 25 ? .batteryLow : .batteryNormal
        // temperature
        self.temperatureSensor.currentTemperature.value = advertisement.temperature.celsius + (configuration?.calibration?.temperature ?? 0.0)
    }
}

// MARK: - Battery Service

extension TirePressureSensorAccessory {
    
    final class BatteryService: HAP.Service.Battery {
        
        init() {
            let name = PredefinedCharacteristic.name("Battery")
            let batteryLevel = PredefinedCharacteristic.batteryLevel(100)
            let chargingState = PredefinedCharacteristic.chargingState()
            super.init(characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(batteryLevel),
                AnyCharacteristic(chargingState)
            ])
            self.statusLowBattery.value = .batteryNormal
            self.chargingState?.value = .notChargeable
        }
    }
}

// MARK: - Tire Pressure Service

public final class TirePressureSensorService: HAP.Service {
    
    let currentPressure = GenericCharacteristic<Float>(
        type: .custom(UUID(uuidString: "293339C4-C4DB-4927-861B-3D95FC84A901")!),
        value: 30, // in PSI
        permissions: [.read, .events],
        description: "Current Pressure",
        format: .float,
        unit: .none
    )
    
    init() {
        let name = PredefinedCharacteristic.name("Tire Pressure Sensor")
        super.init(
            type: .custom(UUID(uuidString: "293339C4-C4DB-4927-861B-3D95FC84A900")!),
            characteristics: [
                AnyCharacteristic(name),
                AnyCharacteristic(currentPressure)
            ]
        )
    }
}

// MARK: - SensorAdvertisement

extension TirePressureSensor: SensorAdvertisement {
    
    public static var sensorType: String { "com.TPMS.Sensor" }
}
