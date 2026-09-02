// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "My_App",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "My_App", targets: ["My_App"])
    ],
    targets: [
        .executableTarget(
            name: "My_App",
            path: "."
        )
    ]
)
