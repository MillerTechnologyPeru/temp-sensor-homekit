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
    
    func testTemperatureSensor() throws {
        
        let data = GAPManufacturerSpecificData(
            companyIdentifier: 473,
            additionalData: Data([0x01, 0x01, 0xBE, 0x00, 0xBB, 0x02, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC3, 0x7E, 0x8B, 0x53])
        )
        
        guard let sensor = GETemperatureSensor(manufacturerData: data) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(sensor.model, 1)
        XCTAssertEqual(sensor.version, 1)
        XCTAssertEqual(sensor.battery, 190)
        XCTAssertEqual(sensor.temperature, 187)
        XCTAssertEqual(sensor.humidity, 683)
        XCTAssertEqual(sensor.checksum, 3279850323)
        XCTAssertEqual(sensor.batteryVoltage, 2.9)
        XCTAssertEqual(sensor.batteryLevel, 87.87879)
        XCTAssertEqual(sensor.temperatureCelcius, 18.7)
        XCTAssertEqual(sensor.humidityPercentage, 68.3)
    }
}
