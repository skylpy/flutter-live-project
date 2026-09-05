// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_live_media_plugin",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-live-media-plugin", targets: ["flutter_live_media_plugin"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // 1.6.0 支持当前项目的 Xcode 16 工具链；后续升级前需重新验证
        // Swift Concurrency、编码器和真机最低系统版本。
        .package(url: "https://github.com/shogo4405/HaishinKit.swift.git", exact: "1.6.0")
    ],
    targets: [
        .target(
            name: "flutter_live_media_plugin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "HaishinKit", package: "HaishinKit.swift")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
