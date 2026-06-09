// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NVMeter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NVMeterCore", targets: ["NVMeterCore"]),
        .executable(name: "NVMeterApp", targets: ["NVMeterApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "NVMeterCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "NVMeterApp",
            dependencies: ["NVMeterCore"]
        ),
        .testTarget(
            name: "NVMeterCoreTests",
            dependencies: ["NVMeterCore"]
        ),
    ]
)
