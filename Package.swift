// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "Dirs",
					  platforms: [
					  	.macOS(.v10_15),
					  ],
					  products: [
					  	// Products define the executables and libraries a package produces, making them visible to other packages.
					  	.library(name: "Dirs",
								   targets: ["Dirs"]),
					  ],

					  dependencies: [
					  	.package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMajor(from: "1.2.0")),
					  	.package(url: "https://github.com/apple/swift-system", from: "1.0.0"),
					  	.package(url: "https://github.com/rhysforyou/swift-case-accessors.git", "0.2.0"..<"0.3.0"),
					  ],
					  targets: [
					  	.target(name: "Dirs",
								  dependencies: [
								  	.product(name: "Algorithms", package: "swift-algorithms"),
								  	.product(name: "SystemPackage", package: "swift-system"),
								  	.product(name: "CaseAccessors", package: "swift-case-accessors"),
								  ]),
					  	.testTarget(name: "DirsTests",
									  dependencies: ["Dirs"]),
					  ])
