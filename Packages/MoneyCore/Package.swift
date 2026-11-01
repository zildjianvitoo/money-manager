// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoneyCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "MoneyCore", targets: ["MoneyCore"]),
    ],
    targets: [
        .target(name: "MoneyCore"),
        .testTarget(name: "MoneyCoreTests", dependencies: ["MoneyCore"]),
    ]
)
