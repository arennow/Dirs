import Foundation
@preconcurrency import SystemPackage

public struct File: Node {
	public let fs: any FilesystemInterface
	public private(set) var path: FilePath

	public init(fs: any FilesystemInterface, path: some IntoFilePath) throws {
		let fp = path.into()

		switch fs.nodeType(at: fp) {
			case .none: throw NoSuchNode(path: fp)
			case .file: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x)
		}

		self.fs = fs
		self.path = fp
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.path)
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		let destFP = destination.into()
		try self.fs.moveNode(from: self, to: destFP)
		self.path = destFP
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
