//
//  SensorAccessory.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import HAP
import CoreSensor

/// HomeKit accessory for a stored sensor. All its values come from the ``Sensor``.
final class SensorAccessory: HAP.Accessory.Thermometer {

    let id: Sensor.ID

    let kind: SensorKind

    let humidity: HAP.Service.HumiditySensor?

    let pressure: TirePressureSensorService?

    let battery: SensorBatteryService

    let history: EveHistoryService

    init(sensor: Sensor, kind: SensorKind, history: EveHistory) {
        self.id = sensor.id
        self.kind = kind
        self.humidity = kind.hasHumidity ? HAP.Service.HumiditySensor() : nil
        self.pressure = kind.hasPressure ? TirePressureSensorService() : nil
        self.battery = SensorBatteryService(hasVoltage: kind.hasBatteryVoltage)
        self.history = EveHistoryService(history: history)
        let info = Service.Info.Info(
            name: sensor.name,
            serialNumber: sensor.serialNumber,
            manufacturer: sensor.manufacturer,
            model: sensor.model,
            firmwareRevision: sensor.firmwareRevision ?? Self.defaultFirmwareRevision
        )
        var services: [HAP.Service] = []
        if let humidity {
            services.append(humidity)
        }
        if let pressure {
            services.append(pressure)
        }
        services.append(self.battery)
        services.append(self.history)
        super.init(info: info, additionalServices: services)
    }

    /// Shows the sensor's stored values.
    func update(_ sensor: Sensor, timeout: TimeInterval, now: Date = Date()) {
        assert(sensor.id == id)
        set(info.name, sensor.name)
        set(info.model, sensor.model)
        set(info.firmwareRevision, sensor.firmwareRevision ?? Self.defaultFirmwareRevision)
        set(temperatureSensor.currentTemperature, sensor.temperature)
        set(humidity?.currentRelativeHumidity, sensor.humidity)
        set(pressure?.currentPressure, sensor.pressure)
        set(battery.batteryLevel, sensor.batteryLevel)
        set(battery.batteryVoltage, sensor.batteryVoltage)
        set(battery.statusLowBattery, sensor.lowBattery.map { $0 ? .batteryLow : .batteryNormal })
        updateReachability(lastSeen: sensor.lastSeen, timeout: timeout, now: now)
    }

    /// Shows the sensor as unreachable when it hasn't been found within `timeout`.
    func updateReachability(lastSeen: Date, timeout: TimeInterval, now: Date = Date()) {
        let isReachable = now.timeIntervalSince(lastSeen) <= timeout
        if reachable != isReachable {
            reachable = isReachable
        }
    }
}

private extension SensorAccessory {

    /// Sets a characteristic to a known value, notifying controllers only when it changes.
    func set<T: Equatable>(_ characteristic: GenericCharacteristic<T>?, _ value: T?) {
        guard let characteristic, let value, characteristic.value != value else {
            return
        }
        characteristic.value = value
    }
}

extension SensorAccessory {

    /// Firmware revision shown until the sensor reports its own.
    static var defaultFirmwareRevision: String { "1.0.0" }
}

// MARK: - Battery Service

final class SensorBatteryService: HAP.Service.Battery {

    let batteryVoltage: GenericCharacteristic<Float>?

    init(hasVoltage: Bool) {
        let name = PredefinedCharacteristic.name("Battery")
        let batteryLevel = PredefinedCharacteristic.batteryLevel(100)
        let chargingState = PredefinedCharacteristic.chargingState()
        let batteryVoltage = hasVoltage ? GenericCharacteristic<Float>(
            type: .custom(UUID(uuidString: "5C7D8287-D288-4F4D-BB4A-161A83A99752")!),
            value: 3.3,
            permissions: [.read, .events],
            description: "Battery Voltage",
            format: .float,
            unit: .none
        ) : nil
        self.batteryVoltage = batteryVoltage
        var characteristics = [
            AnyCharacteristic(name),
            AnyCharacteristic(batteryLevel),
            AnyCharacteristic(chargingState)
        ]
        if let batteryVoltage {
            characteristics.append(AnyCharacteristic(batteryVoltage))
        }
        super.init(characteristics: characteristics)
        self.statusLowBattery.value = .batteryNormal
        self.chargingState?.value = .notChargeable
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
