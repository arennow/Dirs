import SystemPackage

public protocol Node: IntoFilePath, Hashable {
	var path: FilePath { get }
}

public extension Node {
	func into() -> FilePath { self.path }
}
