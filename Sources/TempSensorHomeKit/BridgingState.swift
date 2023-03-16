//
//  AccessoryBridgingState.swift
//  
//
//  Created by Alsey Coleman Miller on 3/16/23.
//

import Foundation
import HAP

final class AccessoryBridgingState: HAP.Service {
    
    public let reachable: GenericCharacteristic<HAP.Reachable>
    public let linkQuality: GenericCharacteristic<HAP.LinkQuality>
    public let accessoryIdentifier: GenericCharacteristic<HAP.AccessoryIdentifier>
    public let category: GenericCharacteristic<HAP.Category>
    
    public init(
        reachable: HAP.Reachable = true,
        linkQuality: HAP.LinkQuality = 0,
        accessoryIdentifier: HAP.AccessoryIdentifier,
        category: HAP.Category
    ) {
        self.reachable = GenericCharacteristic<Reachable>(
            type: .reachable,
            value: reachable,
            permissions: [.read, .events]
        )
        self.linkQuality = GenericCharacteristic<LinkQuality>(
            type: .appleDefined(0x00A7),
            value: linkQuality,
            permissions: [.read, .events]
        )
        self.accessoryIdentifier = GenericCharacteristic<AccessoryIdentifier>(
            type: .appleDefined(0x00A8),
            value: accessoryIdentifier,
            permissions: [.read, .events]
        )
        self.category = GenericCharacteristic<HAP.Category>(
            type: .appleDefined(0x00A9),
            value: category,
            permissions: [.read, .events]
        )
        super.init(type: .bridgingState, characteristics: [
            AnyCharacteristic(self.reachable),
            AnyCharacteristic(self.linkQuality),
            //AnyCharacteristic(self.accessoryIdentifier),
            //AnyCharacteristic(self.category)
        ])
    }
}
