//
//  CoreSensorTests.swift
//  
//
//  Created by Alsey Coleman Miller on 3/1/23.
//

import Foundation
import XCTest
import Bluetooth
import GATT
@testable import CoreSensor

final class CoreSensorTests: XCTestCase {
    
    func testSensor() throws {
        
        let data = GAPManufacturerSpecificData(
            companyIdentifier: 473,
            additionalData: Data([0x01, 0x01, 0xE6, 0x00, 0xB2, 0x03, 0xE8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCC, 0x12, 0xD7, 0xA7])
        )
        
        guard let sensor = GESensor(manufacturerData: data) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(sensor.model, 1)
        XCTAssertEqual(sensor.version, 1)
        XCTAssertEqual(sensor.battery, 230)
        XCTAssertEqual(sensor.temperature, 178)
        XCTAssertEqual(sensor.humidity, 1000)
        XCTAssertEqual(sensor.checksum, 0xCC12D7A7)
        XCTAssertEqual(sensor.batteryVoltage, 3.3)
        XCTAssertEqual(sensor.batteryLevel, 100.0)
        XCTAssertEqual(sensor.temperatureCelcius, 17.8)
        XCTAssertEqual(sensor.humidityPercentage, 100.0)
        
        XCTAssertEqual(sensor.read(), [
            .batteryLevel(100.0),
            .temperature(17.8),
            .humidity(100.0)
        ])
    }
}
