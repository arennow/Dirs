import SystemPackage

public protocol Node: IntoFilePath {
	var path: FilePath { get }
}

public extension Node {
	func into() -> FilePath { self.path }
}
