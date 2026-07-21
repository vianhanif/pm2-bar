// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PM2Bar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PM2Bar",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
