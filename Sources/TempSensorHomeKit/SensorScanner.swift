//
//  SensorScanner.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import Bluetooth
import GATT
import CoreSensor
import Govee
import Inkbird
import TPMS
import XiaomiBluetooth

/// Scans for sensors and writes their values and history to the store.
@MainActor
final class SensorScanner {

    // MARK: - Properties

    var log: ((String) -> ())?

    let central: NativeCentral

    let store: SensorStore

    let configuration: SensorConfiguration

    /// Time the scanner started. Recorded history starts here.
    let startDate = Date()

    /// Last value written for each sensor.
    private var sensors = [Sensor.ID: Sensor]()

    /// Peripherals found in this session.
    private var peripherals = [Sensor.ID: NativeCentral.Peripheral]()

    /// Configuration of each sensor found in this session.
    private var sensorConfigurations = [Sensor.ID: SensorConfiguration.Sensor]()

    /// Govee models found in this session, needed to download their history.
    private var goveeModels = [Sensor.ID: GoveeModel]()

    /// Last saved history of each sensor.
    private var histories = [Sensor.ID: EveHistory]()

    /// Readings not yet recorded in the history of sensors without their own.
    private var buffers = [Sensor.ID: ReadingBuffer]()

    /// Sensors with a history download in progress.
    private var syncing = Set<Sensor.ID>()

    /// Last time a history download failed.
    private var syncFailures = [Sensor.ID: Date]()

    // MARK: - Initialization

    init(central: NativeCentral, store: SensorStore, configuration: SensorConfiguration) {
        self.central = central
        self.store = store
        self.configuration = configuration
    }

    // MARK: - Methods

    func run() async throws {
        do {
            for sensor in try await store.sensors() {
                sensors[sensor.id] = sensor
            }
        }
        catch {
            log?("Unable to read sensors. \(error)")
        }
        while true {
            do {
                try await scanOnce()
            }
            catch {
                // HCI requests can time out while advertising reports flood the HCI socket
                log?("Scan failed. \(error)")
            }
            // connect after scan
            await connect()
            // record history of sensors without their own
            await recordHistory()
            // scan again
            try await Task.sleep(timeInterval: 1.0)
        }
    }
}

// MARK: - Scanning

private extension SensorScanner {

    /// Time between writes of a sensor whose values haven't changed, to keep its last seen time.
    static var lastSeenInterval: TimeInterval { 60 }

    func scanOnce() async throws {
        // start scan
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
        // scan timeout
        _ = Task {
            try await Task.sleep(timeInterval: 45.0)
            stream.stop()
        }
        for try await scanData in stream {
            if await found(GETemperatureSensor.self, in: scanData) {
                continue
            } else if await found(GoveeAccessory.Thermometer.self, in: scanData) {
                continue
            } else if await found(InkbirdAdvertisement.Thermometer.self, in: scanData) {
                continue
            } else if await found(TirePressureSensor.self, in: scanData) {
                continue
            } else if let manufacturerData = scanData.advertisementData.manufacturerData,
                manufacturerData.companyIdentifier == GETemperatureSensor.companyIdentifier {
                log?("Unable to parse GE \(manufacturerData)")
            } else if let miBeacon = MiBeacon(scanData.advertisementData),
                miBeacon.address != nil,
                await found(MiBeacon.self, in: scanData) {
                continue
            } else {
                continue
            }
        }
    }

    /// Writes the sensor found in the advertisement, if it is one of type `T`.
    ///
    /// - Returns: Whether the advertisement is from a sensor of type `T`.
    func found<T: BridgedSensorAdvertisement>(
        _ type: T.Type,
        in scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>
    ) async -> Bool {
        guard let advertisement = T(scanData.advertisementData) else {
            return false
        }
        let configuration = configuration(for: scanData)
        guard self.configuration.sensors.isEmpty || configuration != nil else {
            log?("Ignoring \(T.sensorType) \(scanData.peripheral.description)")
            return false
        }
        let serialNumber = advertisement.serialNumber(peripheral: scanData.peripheral)
        let modelName = advertisement.modelName
        let values = advertisement.values
        let id = Sensor.ID(type: T.sensorType, serialNumber: serialNumber)
        let now = Date()
        if peripherals[id] == nil {
            log?("Found \(T.sensorType) \(scanData.peripheral.description)")
        }
        peripherals[id] = scanData.peripheral
        sensorConfigurations[id] = configuration
        if let advertisement = advertisement as? GoveeAccessory.Thermometer {
            goveeModels[id] = advertisement.id.model
        }
        var sensor = sensors[id] ?? Sensor(
            id: id,
            type: T.sensorType,
            peripheral: scanData.peripheral.description,
            name: T.kind.defaultName,
            manufacturer: T.kind.manufacturer,
            model: modelName,
            serialNumber: serialNumber,
            lastSeen: now
        )
        sensor.peripheral = scanData.peripheral.description
        sensor.name = configuration?.name ?? T.kind.defaultName
        sensor.model = configuration?.model ?? modelName
        sensor.lastSeen = now
        sensor.update(values, calibration: configuration?.calibration)
        await write(sensor)
        return true
    }

    func configuration(for scanData: ScanData<NativeCentral.Peripheral, NativeCentral.Advertisement>) -> SensorConfiguration.Sensor? {
        configuration.sensors
            .first(where: { $0.id == scanData.peripheral.description || $0.id == scanData.advertisementData.localName })
    }

    /// Writes a sensor if its values changed, or its last seen time is old, and records its reading.
    func write(_ sensor: Sensor) async {
        guard let kind = SensorKind(type: sensor.type) else {
            assertionFailure("Unknown sensor type \(sensor.type)")
            return
        }
        let oldValue = sensors[sensor.id]
        if kind.historySource == .recorded {
            record(sensor, replacing: oldValue)
        }
        if let oldValue {
            var unchanged = sensor
            unchanged.lastSeen = oldValue.lastSeen
            guard unchanged != oldValue || sensor.lastSeen.timeIntervalSince(oldValue.lastSeen) >= Self.lastSeenInterval else {
                return
            }
        }
        do {
            try await store.update(sensor)
            sensors[sensor.id] = sensor
        }
        catch {
            log?("Unable to save \(sensor.id). \(error)")
        }
    }
}

// MARK: - Connections

private extension SensorScanner {

    /// Time to wait for a history download before scanning again.
    static var syncTimeout: TimeInterval { 4 * 60 }

    /// Time to wait before trying again after a failed history download.
    static var syncRetryInterval: TimeInterval { 5 * 60 }

    func connect() async {
        for (id, peripheral) in peripherals {
            guard let sensor = sensors[id], let kind = SensorKind(type: sensor.type) else {
                continue
            }
            switch kind {
            case .govee, .inkbird:
                guard needsSync(sensor, kind: kind) else {
                    continue
                }
                await sync(sensor, kind: kind, peripheral: peripheral)
            case .xiaomi:
                do {
                    let values = try await central.connection(for: peripheral) { connection in
                        try await XiaomiThermometer.read(connection)
                    }
                    var newValue = sensors[id] ?? sensor
                    newValue.lastSeen = Date()
                    newValue.update(values, calibration: sensorConfigurations[id]?.calibration)
                    await write(newValue)
                }
                catch {
                    log?("Unable to connect and update \(peripheral). \(error)")
                }
            case .ge, .tirePressure:
                continue
            }
        }
    }

    /// Whether it is time to download the sensor's history again.
    func needsSync(_ sensor: Sensor, kind: SensorKind) -> Bool {
        guard syncing.contains(sensor.id) == false else {
            return false
        }
        if let failure = syncFailures[sensor.id], Date().timeIntervalSince(failure) < Self.syncRetryInterval {
            return false
        }
        let interval: TimeInterval = kind == .govee ? GoveeThermometer.syncInterval : InkbirdThermometer.syncInterval
        return sensor.lastHistorySync.map { Date().timeIntervalSince($0) >= interval } ?? true
    }

    /// Downloads the sensor's history, waiting at most ``syncTimeout``.
    ///
    /// A Bluetooth request can wait forever behind one that never completed,
    /// so a download that takes too long keeps running in the background while scanning continues.
    func sync(_ sensor: Sensor, kind: SensorKind, peripheral: NativeCentral.Peripheral) async {
        let id = sensor.id
        syncing.insert(id)
        let completion = SyncCompletion()
        Task {
            do {
                let count = try await download(sensor, kind: kind, peripheral: peripheral)
                syncFailures[id] = nil
                log?("Downloaded \(count) history entries from \(peripheral), firmware \(sensors[id]?.firmwareRevision ?? "")")
            }
            catch {
                syncFailures[id] = Date()
                log?("Unable to download history from \(peripheral). \(error)")
            }
            syncing.remove(id)
            completion.finish()
        }
        Task {
            try? await Task.sleep(timeInterval: Self.syncTimeout)
            if completion.finish() {
                log?("History download from \(peripheral) is taking longer than \(Int(Self.syncTimeout)) seconds, continuing in the background")
            }
        }
        await completion.wait()
    }

    /// Downloads and saves the sensor's history.
    ///
    /// - Returns: The number of history entries added.
    func download(_ sensor: Sensor, kind: SensorKind, peripheral: NativeCentral.Peripheral) async throws -> Int {
        let oldValue = try await history(for: sensor.id, kind: kind)
        let calibration = sensorConfigurations[sensor.id]?.calibration
        var history = oldValue
        let result: HistoryDownload
        switch kind {
        case .govee:
            guard let model = goveeModels[sensor.id] else {
                return 0
            }
            result = try await GoveeThermometer.download(
                central: central,
                peripheral: peripheral,
                model: model,
                after: history.lastDate,
                readFirmware: sensor.firmwareRevision == nil
            )
        case .inkbird:
            result = try await InkbirdThermometer.download(central: central, peripheral: peripheral)
        case .ge, .tirePressure, .xiaomi:
            return 0
        }
        let samples = result.samples.map {
            EveHistory.Sample(
                date: $0.date,
                temperature: $0.temperature + (calibration?.temperature ?? 0),
                humidity: $0.humidity + (calibration?.humidity ?? 0)
            )
        }
        let count = history.append(averaging: samples, now: result.date)
        var newValue = sensors[sensor.id] ?? sensor
        newValue.lastSeen = Date()
        newValue.lastHistorySync = Date()
        if let firmwareRevision = result.firmwareRevision {
            newValue.firmwareRevision = firmwareRevision
        }
        await write(newValue)
        try await saveHistory(history, replacing: oldValue, for: sensor.id)
        return count
    }
}

// MARK: - History

private extension SensorScanner {

    /// Last saved history of a sensor, read from the store the first time.
    func history(for id: Sensor.ID, kind: SensorKind) async throws -> EveHistory {
        if let history = histories[id] {
            return history
        }
        let history = try await store.history(for: id, fields: kind.historyFields)
        histories[id] = history
        return history
    }

    func saveHistory(_ newValue: EveHistory, replacing oldValue: EveHistory, for id: Sensor.ID) async throws {
        guard newValue != oldValue else {
            return
        }
        try await store.saveHistory(newValue, replacing: oldValue, for: id)
        // after a failed save, the next one writes the same entries again
        histories[id] = newValue
    }

    /// Buffer for a sensor's readings, starting with its stored reading.
    func buffer(for sensor: Sensor) -> ReadingBuffer {
        buffers[sensor.id] ?? ReadingBuffer(start: startDate, previous: sensor.reading)
    }

    /// Adds a sensor's reading to its buffer, if it changed.
    func record(_ sensor: Sensor, replacing oldValue: Sensor?) {
        var buffer = buffer(for: oldValue ?? sensor)
        if let reading = sensor.reading {
            buffer.append(reading)
        }
        buffers[sensor.id] = buffer
    }

    /// Averages the readings of sensors without their own history into history entries.
    ///
    /// A sensor not scanned since the bridge started repeats its last stored value.
    func recordHistory() async {
        let now = Date()
        for sensor in sensors.values {
            guard let kind = SensorKind(type: sensor.type), kind.historySource == .recorded else {
                continue
            }
            var buffer = buffer(for: sensor)
            let samples = buffer.averages(through: now)
            buffers[sensor.id] = buffer
            guard samples.isEmpty == false else {
                continue
            }
            do {
                let oldValue = try await history(for: sensor.id, kind: kind)
                var history = oldValue
                for sample in samples where history.lastDate.map({ sample.date > $0 }) ?? true {
                    history.append(date: sample.date, temperature: sample.temperature, humidity: sample.humidity)
                }
                try await saveHistory(history, replacing: oldValue, for: sensor.id)
            }
            catch {
                log?("Unable to save history of \(sensor.id). \(error)")
            }
        }
    }
}

/// Resumes one waiter when the first of several events happens.
@MainActor
private final class SyncCompletion {

    private var isFinished = false

    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard isFinished == false else {
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    /// Returns whether this call finished the wait.
    @discardableResult
    func finish() -> Bool {
        guard isFinished == false else {
            return false
        }
        isFinished = true
        continuation?.resume()
        continuation = nil
        return true
    }
}
