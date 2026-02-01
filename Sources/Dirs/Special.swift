import SystemPackage

/// Represents filesystem nodes that are neither files, directories, symlinks, nor Finder aliases.
/// This includes FIFOs (named pipes), Unix domain sockets, character devices, and block devices.
/// These nodes support only basic operations (move, rename, delete) and cannot be read from or written to through this library.
public struct Special: Node {
	public static let nodeType: NodeType = .special

	let _fs: FSInterface
	public var fs: any FilesystemInterface { self._fs.wrapped }
	public private(set) var path: FilePath

	init(_fs: FSInterface, path: some IntoFilePath) throws {
		let fp = path.into()

		switch _fs.wrapped.nodeTypeFollowingSymlinks(at: fp) {
			case .none: throw NoSuchNode(path: fp)
			case .special: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x)
		}

		self._fs = _fs
		self.path = fp
	}

	init(uncheckedAt path: FilePath, in fs: FSInterface) {
		self._fs = fs
		self.path = path
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		self.path = try self.fs.moveNode(from: self, to: self.ensureAbsolutePath(of: destination))
	}

	public mutating func rename(to newName: String) throws {
		self.path = try self.fs.renameNode(at: self, to: newName)
	}
}
