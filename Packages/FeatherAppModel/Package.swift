// swift-tools-version: 6.0
import PackageDescription

/// The app's behaviour (AppModel, Feather Cloud, account flows), shared by the Mac app and the iPhone and iPad app.
/// Platform abilities (opening URLs, a global shortcut) come in through `AppPlatform`.
let package = Package(
    name: "FeatherAppModel",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "FeatherAppModel", targets: ["FeatherAppModel"]),
    ],
    dependencies: [
        .package(path: "../FeatherCore"),
        .package(path: "../FeatherCrypto"),
        .package(path: "../FeatherSync"),
        .package(path: "../FeatherEditor"),
    ],
    targets: [
        .target(name: "FeatherAppModel", dependencies: [
            "FeatherCore", "FeatherCrypto", "FeatherSync",
            .product(name: "FeatherEditorCore", package: "FeatherEditor"),
        ]),
        .testTarget(name: "FeatherAppModelTests", dependencies: [
            "FeatherAppModel", "FeatherCore", "FeatherCrypto", "FeatherSync",
            .product(name: "FeatherEditorCore", package: "FeatherEditor"),
        ]),
    ]
)
