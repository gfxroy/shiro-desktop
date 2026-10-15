// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shiro",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Shiro", targets: ["Shiro"]), .executable(name: "ShiroChecks", targets: ["ShiroChecks"])],
    targets: [
        .target(name: "ShiroCore"),
        .executableTarget(name: "Shiro", dependencies: ["ShiroCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "ShiroChecks", dependencies: ["ShiroCore"], path: "Tests/ShiroCoreTests")
    ]
)
