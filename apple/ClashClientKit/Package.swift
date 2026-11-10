// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ClashClientKit", platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)], products: [.library(name: "ClashClientKit", targets: ["ClashClientKit"])], dependencies: [], targets: [.target(name: "ClashClientKit", dependencies: [], resources: [.copy("Resources/RuleCatalog")], swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS, .macOS], configuration: .release))]), .testTarget(name: "ClashClientKitTests", dependencies: ["ClashClientKit"], path: "Tests/ClashClientKitTests")])
