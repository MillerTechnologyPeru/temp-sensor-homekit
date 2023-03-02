//
//  Hexadecimal.swift
//
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

internal extension FixedWidthInteger {
    
    func toHexadecimal() -> String {
        
        var string = String(self, radix: 16)
        while string.utf8.count < (MemoryLayout<Self>.size * 2) {
            string = "0" + string
        }
        return string.uppercased()
    }
}

internal extension Collection where Element == UInt8 {
    
    func toHexadecimal() -> String {
        return reduce("") { $0 + $1.toHexadecimal() }
    }
}
