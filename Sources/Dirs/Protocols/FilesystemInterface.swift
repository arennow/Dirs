import Foundation
import SystemPackage

public struct FilePathStat {
	public let filePath: FilePath
	public let isDirectory: Bool

	public init(filePath: FilePath, isDirectory: Bool) {
		self.filePath = filePath
		self.isDirectory = isDirectory
	}
}

public enum NodeType {
	case dir, file
}

public protocol FilesystemInterface: AnyObject {
	func nodeType(at ifp: some IntoFilePath) -> NodeType?

	func contentsOf(file ifp: some IntoFilePath) throws -> Data
	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat>

	func createFile(at ifp: some IntoFilePath) throws -> File
	func createDir(at ifp: some IntoFilePath) throws -> Dir

	func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws
}

public extension FilesystemInterface {
	func dir(at ifp: some IntoFilePath) throws -> Dir {
		try Dir(fs: self, path: ifp.into())
	}

	func file(at ifp: some IntoFilePath) throws -> File {
		try File(fs: self, path: ifp.into())
	}
}

public extension FilesystemInterface {
	var rootDir: Dir {
		get throws {
			try self.dir(at: "/")
		}
	}
}
