import Foundation
@preconcurrency import SystemPackage

public struct File: Node {
	public let fs: any FilesystemInterface
	public let path: FilePath

	public init(fs: any FilesystemInterface, path: FilePath) throws {
		switch fs.nodeType(at: path) {
			case .dir: throw WrongNodeType(path: path, actualType: .dir)
			case .none: throw NoSuchNode(path: path)
			case .file: break
		}

		self.fs = fs
		self.path = path
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.path)
	}
}

public extension File {
	func contents() throws -> Data {
		try self.fs.contentsOf(file: self)
	}

	func stringContents() throws -> String? {
		String(data: try self.contents(), encoding: .utf8)
	}

	func replaceContents(_ content: some IntoData) throws {
		try self.fs.replaceContentsOfFile(at: self, to: content)
	}

	func appendContents(_ addendum: some IntoData) throws {
		try self.fs.appendContentsOfFile(at: self, with: addendum)
	}
}
