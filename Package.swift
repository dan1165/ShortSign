// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShortSign",
    platforms: [
        .iOS("17.0"),
    ],
    products: [
        // An xtool project must expose exactly one library product.
        .library(name: "ShortSign", targets: ["ShortSign"]),
    ],
    targets: [
        // OpenSSL built for arm64 iOS, from 0xilis/shortcut-sign's ios-support.
        .binaryTarget(name: "OpenSSL", path: "Vendor/OpenSSL.xcframework"),
        .target(
            name: "CShortcutSign",
            dependencies: ["OpenSSL"],
            path: "Sources/CShortcutSign",
            exclude: [
                "neo/compression/lzfse/src/lzfse_main.c",
                "neo/compression/lzfse/LICENSE",
                "neo/compression/lzfse/README.md",
                "neo/compression/libzbitmap/LICENSE",
                "neo/compression/libzbitmap/README.rst",
                "neo/compression/libzbitmap/.gitignore",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("neo"),
                .headerSearchPath("neo/compression/lzfse/src"),
                .headerSearchPath("neo/compression/libzbitmap"),
                .headerSearchPath("openssl"),
                .define("OPENSSL_API_COMPAT", to: "30400"),
            ],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "ShortSign",
            dependencies: ["CShortcutSign"],
            path: "Sources/ShortSign",
            resources: [
                .copy("Resources/auth.plist"),
                .copy("Resources/key.dat"),
                .copy("Resources/ShortSign.cer"),
            ]
        ),
    ]
)
