// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FailureTriage",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FailureTriage", targets: ["FailureTriage"])
    ],
    targets: [
        .target(name: "FailureTriage"),
        .testTarget(name: "FailureTriageTests", dependencies: ["FailureTriage"])
    ]
)
