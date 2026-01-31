// This file is dynamically generated.
// Modifying it is futile.

import Foundation
import SystemPackage

public protocol IntoURL {
	func into() -> URL
}

public extension URL {
	static func from(_ source: some IntoURL) -> URL { source.into() }
}

public extension Sequence where Element: IntoURL {
	func mapInto() -> Array<URL> { map { $0.into() } }
}

extension URL: IntoURL {
	public func into() -> URL { self }
}

public protocol IntoFilePath: IntoURL {
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

public protocol IntoFilePathComponentView {
	func into() -> FilePath.ComponentView
}

public extension FilePath.ComponentView {
	static func from(_ source: some IntoFilePathComponentView) -> FilePath.ComponentView { source.into() }
}

public extension Sequence where Element: IntoFilePathComponentView {
	func mapInto() -> Array<FilePath.ComponentView> { map { $0.into() } }
}

extension FilePath.ComponentView: IntoFilePathComponentView {
	public func into() -> FilePath.ComponentView { self }
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
