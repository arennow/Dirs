// This file is dynamically generated.
// Modifying it is futile.

import Foundation

import SystemPackage

public protocol IntoFilePath {
	func into() -> FilePath
}

public extension FilePath {
	static func from(_ source: some IntoFilePath) -> FilePath { source.into() }
}

public extension Sequence where Element: IntoFilePath {
	func mapInto() -> Array<FilePath> { map { $0.into() } }
}

extension FilePath: IntoFilePath {
	public func into() -> FilePath { self }
}

public protocol IntoData {
	func into() -> Data
}

public extension Data {
	static func from(_ source: some IntoData) -> Data { source.into() }
}

public extension Sequence where Element: IntoData {
	func mapInto() -> Array<Data> { map { $0.into() } }
}

extension Data: IntoData {
	public func into() -> Data { self }
}

public protocol IntoString: IntoData {
	func into() -> String
}

public extension String {
	static func from(_ source: some IntoString) -> String { source.into() }
}

public extension Sequence where Element: IntoString {
	func mapInto() -> Array<String> { map { $0.into() } }
}

extension String: IntoString {
	public func into() -> String { self }
}
