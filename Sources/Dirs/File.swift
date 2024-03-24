import Foundation
import SystemPackage

public struct File: Node {
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.fs === rhs.fs && lhs.path == rhs.path
	}

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

extension File {
	func contents() throws -> Data {
		try self.fs.contentsOf(file: self)
	}

	func stringContents() throws -> String? {
		String(data: try self.contents(), encoding: .utf8)
	}
}
