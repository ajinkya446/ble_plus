// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "ble_plus",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "ble_plus", targets: ["ble_plus"])
    ],
    targets: [
        .target(
            name: "ble_plus",
            path: "."
        )
    ]
)
