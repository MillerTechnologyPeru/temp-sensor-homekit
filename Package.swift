// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "temp-sensor-homekit",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .executable(
            name: "temp-sensor-homekit",
            targets: ["TempSensorHomeKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/MillerTechnologyPeru/HAP.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            .upToNextMajor(from: "6.0.0")
        ),
        .package(
            url: "https://github.com/PureSwift/GATT.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/Inkbird.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/Govee.git",
            branch: "master"
        ),
    ],
    targets: [
        .executableTarget(
            name: "TempSensorHomeKit",
            dependencies: [
                "CoreSensor",
                "Govee",
                "Inkbird",
                .product(
                    name: "HAP",
                    package: "HAP"
                ),
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "DarwinGATT",
                    package: "GATT",
                    condition: .when(platforms: [.macOS])
                ),
            ]
        ),
        .target(
            name: "CoreSensor",
            dependencies: [
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "GATT",
                    package: "GATT"
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                )
            ]
        ),
        .testTarget(
            name: "CoreSensorTests",
            dependencies: ["CoreSensor"]
        )
    ]
)
