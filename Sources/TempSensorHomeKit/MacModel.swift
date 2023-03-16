//
//  MacModel.swift
//  
//
//  Created by Alsey Coleman Miller on 3/16/23.
//

#if os(macOS)
import Foundation
import IOKit

func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                              IOServiceMatching("IOPlatformExpertDevice"))
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
    }

    IOObjectRelease(service)
    return modelIdentifier
}
#endif
