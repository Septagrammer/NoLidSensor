// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NoLidSensor", platforms: [.macOS(.v13)], products: [.executable(name: "NoLidSensor", targets: ["DarkSleep"])], targets: [
    .target(name: "DarkSleepCore"),
    .executableTarget(name: "DarkSleep", dependencies: ["DarkSleepCore"]),
    .testTarget(name: "DarkSleepCoreTests", dependencies: ["DarkSleepCore"]),
    .testTarget(name: "CameraPermissionTests", dependencies: ["DarkSleep"])
])
