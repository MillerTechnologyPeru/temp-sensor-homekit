// swift-tools-version: 6.4
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
            from: "8.0.0"
        ),
        .package(
            url: "https://github.com/PureSwift/GATT.git",
            from: "4.0.0",
            traits: ["BluetoothGATT"]
        ),
        .package(
            url: "https://github.com/PureSwift/BluetoothLinux.git",
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
        .package(
            url: "https://github.com/MillerTechnologyPeru/TPMS.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/MillerTechnologyPeru/XiaomiBluetooth.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/PureSwift/CoreModel.git",
            from: "2.11.0"
        ),
        .package(
            url: "https://github.com/PureSwift/CoreModel-SQLite.git",
            from: "0.3.3"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "TempSensorHomeKit",
            dependencies: [
                "CoreSensor",
                "Govee",
                "Inkbird",
                "TPMS",
                "XiaomiBluetooth",
                "BluetoothLinux",
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
            ],
            exclude: [
                "Info.plist"
            ],
            linkerSettings: [
                // Embed Info.plist so macOS grants Bluetooth access when launched by launchd
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TempSensorHomeKit/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "CoreSensor",
            dependencies: [
                .product(
                    name: "CoreModel",
                    package: "CoreModel"
                ),
                .product(
                    name: "CoreModelSQLite",
                    package: "CoreModel-SQLite"
                ),
                .product(
                    name: "DequeModule",
                    package: "swift-collections"
                ),
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
