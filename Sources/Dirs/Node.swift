import SystemPackage

public protocol Node: IntoFilePath, Hashable {
	var fs: any FilesystemInterface { get }
	var path: FilePath { get }
}

public extension Node {
	func into() -> FilePath { self.path }
}

public extension Node {
	var parent: Dir? {
		try? Dir(fs: self.fs, path: self.path.removingLastComponent())
	}

	func delete() throws {
		try self.fs.deleteNode(at: self)
	}
}
