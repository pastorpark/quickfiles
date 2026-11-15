// swift-tools-version:5.9
// Test harness for QuickFiles' pure (Foundation-only) logic. The app target compiles the same
// source files directly; this package only exists so `swift test` can exercise them.
import PackageDescription

let package = Package(
    name: "QuickFilesCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "QuickFilesCore",
            path: "QuickFiles/Models",
            exclude: ["AppModels.swift"],
            sources: ["SelectionModel.swift", "MovePlanner.swift", "GridNavigation.swift"]
        ),
        .testTarget(
            name: "QuickFilesCoreTests",
            dependencies: ["QuickFilesCore"],
            path: "Tests/QuickFilesCoreTests"
        )
    ]
)
