// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "Dirs",
					  platforms: [
					  	.macOS(.v10_15),
					  ],
					  products: [
					  	.library(name: "Dirs",
								   targets: ["Dirs"]),
					  	.library(name: "DirsMockFSInterface",
								   targets: ["DirsMockFSInterface"]),
					  ],

					  dependencies: [
					  	.package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMajor(from: "1.2.0")),
					  	.package(url: "https://github.com/apple/swift-system", from: "1.4.2"),
					  	.package(url: "https://github.com/arennow/SortAndFilter.git", .upToNextMajor(from: "1.0.0")),
					  ],
					  targets: [
					  	.target(name: "Dirs",
								  dependencies: [
								  	.product(name: "Algorithms", package: "swift-algorithms"),
								  	.product(name: "SystemPackage", package: "swift-system"),
								  ]),
					  	.target(name: "DirsMockFSInterface",
								  dependencies: ["Dirs"]),
					  	.testTarget(name: "DirsTests",
									  dependencies: [
									  	"Dirs",
									  	"DirsMockFSInterface",
									  	"SortAndFilter",
									  ]),
					  ])
