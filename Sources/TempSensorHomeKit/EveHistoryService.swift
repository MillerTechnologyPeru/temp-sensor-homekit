//
//  EveHistoryService.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import HAP
import CoreSensor

/// Eve history service, read by the Eve app to show temperature and humidity graphs.
///
/// The Eve app writes the index it wants to the request characteristic,
/// then reads the entries characteristic until it returns `00`.
final class EveHistoryService: HAP.Service {

    let status = GenericCharacteristic<Data>(
        type: .eveHistoryStatus,
        value: EveHistory().status,
        permissions: [.read, .events, .hidden]
    )

    let entries = GenericCharacteristic<Data>(
        type: .eveHistoryEntries,
        value: EveHistoryService.endOfEntries,
        permissions: [.read, .events, .hidden]
    )

    let request = GenericCharacteristic<Data>(
        type: .eveHistoryRequest,
        permissions: [.write, .hidden]
    )

    let setTime = GenericCharacteristic<Data>(
        type: .eveSetTime,
        permissions: [.write, .hidden]
    )

    var history: EveHistory {
        didSet {
            status.value = history.status
        }
    }

    /// Next index to send, while a transfer is in progress.
    private var transferIndex: UInt32?

    init(history: EveHistory = EveHistory()) {
        self.history = history
        super.init(type: .eveHistory, characteristics: [
            AnyCharacteristic(status),
            AnyCharacteristic(entries),
            AnyCharacteristic(request),
            AnyCharacteristic(setTime)
        ])
        self.status.value = history.status
    }

    override func characteristic<T>(_ characteristic: GenericCharacteristic<T>, didChangeValue newValue: T?) {
        if characteristic === request {
            transferIndex = request.value.flatMap { EveHistory.requestedIndex($0) }
        } else if characteristic === setTime {
            // the bridge keeps its own clock
        } else {
            super.characteristic(characteristic, didChangeValue: newValue)
        }
    }

    override func characteristicWillReadValue<T>(_ characteristic: GenericCharacteristic<T>) {
        guard characteristic === entries else {
            super.characteristicWillReadValue(characteristic)
            return
        }
        if let index = transferIndex, let (data, next) = history.entries(from: index) {
            transferIndex = next
            entries.value = data
        } else {
            transferIndex = nil
            entries.value = Self.endOfEntries
        }
    }
}

private extension EveHistoryService {

    static var endOfEntries: Data { Data([0x00]) }
}

extension HAP.ServiceType {

    static var eveHistory: ServiceType { ServiceType(UUID(uuidString: "E863F007-079E-48FF-8F27-9C2605A29F52")!) }
}

extension HAP.CharacteristicType {

    static var eveHistoryStatus: CharacteristicType { CharacteristicType(UUID(uuidString: "E863F116-079E-48FF-8F27-9C2605A29F52")!) }

    static var eveHistoryEntries: CharacteristicType { CharacteristicType(UUID(uuidString: "E863F117-079E-48FF-8F27-9C2605A29F52")!) }

    static var eveHistoryRequest: CharacteristicType { CharacteristicType(UUID(uuidString: "E863F11C-079E-48FF-8F27-9C2605A29F52")!) }

    static var eveSetTime: CharacteristicType { CharacteristicType(UUID(uuidString: "E863F121-079E-48FF-8F27-9C2605A29F52")!) }
}
