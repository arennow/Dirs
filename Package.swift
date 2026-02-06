// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let allPlatforms: Array<Platform> = [
	.macOS,
	.iOS,
	.tvOS,
	.watchOS,
	.visionOS,
	.linux,
	.windows,
]

func allPlatformsExcept(_ excluded: Platform...) -> Array<Platform> {
	allPlatforms.filter { !excluded.contains($0) }
}

let swiftSettings: Array<SwiftSetting> = [
	.enableUpcomingFeature("ExistentialAny"),
	.define("XATTRS_ENABLED", .when(platforms: allPlatformsExcept(.windows))),
	.define("FINDER_ALIASES_ENABLED", .when(platforms: allPlatformsExcept(.linux, .windows))),
	.define("SPECIALS_ENABLED", .when(platforms: allPlatformsExcept(.windows))),
]

let package = Package(name: "Dirs",
					  platforms: [
					  	.macOS(.v10_15),
					  	.iOS(.v13),
					  	.tvOS(.v13),
					  	.watchOS(.v6),
					  	.visionOS(.v1),
					  ],
					  products: [
					  	.library(name: "Dirs",
								   targets: ["Dirs"]),
					  ],

					  dependencies: [
					  	.package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMajor(from: "1.2.0")),
					  	.package(url: "https://github.com/apple/swift-system", from: "1.6.4"),
					  	.package(url: "https://github.com/arennow/Locked.git", .upToNextMajor(from: "2.0.0")),
					  ],
					  targets: [
					  	.target(name: "Dirs",
								  dependencies: [
								  	.product(name: "Algorithms", package: "swift-algorithms"),
								  	.product(name: "SystemPackage", package: "swift-system"),
								  	"Locked",
								  ],
								  swiftSettings: swiftSettings),
					  	.testTarget(name: "DirsTests",
									  dependencies: [
									  	"Dirs",
									  ],
									  swiftSettings: swiftSettings),
					  ])
