// This file is dynamically generated.
// Modifying it is futile.

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
