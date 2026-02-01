import Foundation
import SystemPackage

public struct File: Node {
	public static let nodeType: NodeType = .file

	let _fs: FSInterface
	public var fs: any FilesystemInterface { self._fs.wrapped }
	public private(set) var path: FilePath

	init(_fs: FSInterface, path: some IntoFilePath) throws {
		let fp = path.into()

		switch _fs.wrapped.nodeTypeFollowingSymlinks(at: fp) {
			case .none: throw NoSuchNode(path: fp)
			case .file: break
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

public extension File {
	func contents() throws -> Data {
		try self.fs.contentsOf(file: self)
	}

	/// Returns the file's contents as a UTF-8 string.
	///
	/// Throws if the file cannot be read. Returns `nil` if the data is not valid UTF-8.
	/// An empty file returns an empty string.
	func stringContents() throws -> String? {
		String(data: try self.contents(), encoding: .utf8)
	}

	func size() throws -> UInt64 {
		try self.fs.sizeOfFile(at: self)
	}

	func replaceContents(_ content: some IntoData) throws {
		try self.fs.replaceContentsOfFile(at: self, to: content)
	}

	func appendContents(_ addendum: some IntoData) throws {
		try self.fs.appendContentsOfFile(at: self, with: addendum)
	}
}
