import SystemPackage

public protocol Node: IntoFilePath, Hashable, Sendable {
	var fs: any FilesystemInterface { get }
	var path: FilePath { get }

	mutating func move(to destination: some IntoFilePath) throws
}

public extension Node {
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.fs.isEqual(to: rhs.fs) && lhs.path == rhs.path
	}

	func into() -> FilePath { self.path }
}

public extension Node {
	var name: String {
		self.path.lastComponent?.string ?? ""
	}

	var parent: Dir? {
		try? Dir(fs: self.fs, path: self.path.removingLastComponent())
	}

	func delete() throws {
		try self.fs.deleteNode(at: self)
	}

	func realpath() throws -> FilePath {
		(try? self.fs.destinationOf(symlink: self.path)) ?? self.path
	}
}
