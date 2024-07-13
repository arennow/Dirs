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

	func filePathOfNonexistantTemporaryFile(extension: String?) -> FilePath

	func createFile(at ifp: some IntoFilePath) throws -> File
	func createDir(at ifp: some IntoFilePath) throws -> Dir

	func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws

	func deleteNode(at ifp: some IntoFilePath) throws
}

public extension FilesystemInterface {
	func filePathOfNonexistantTemporaryFile() -> FilePath {
		self.filePathOfNonexistantTemporaryFile(extension: nil)
	}

	func dir(at ifp: some IntoFilePath) throws -> Dir {
		try Dir(fs: self, path: ifp.into())
	}

	func file(at ifp: some IntoFilePath) throws -> File {
		try File(fs: self, path: ifp.into())
	}

	func createFileAndIntermediaryDirs(at ifp: some IntoFilePath, contents: some IntoData = Data()) throws -> File {
		guard let (path, leaf) = ifp.into().pathAndLeaf else {
			throw InvalidPathForCall.needAbsoluteWithComponent
		}

		let dir = try self.rootDir.createDir(at: path)
		let file = try dir.createFile(at: leaf)
		try file.setContents(contents)
		return file
	}
}

extension FilePath {
	var pathAndLeaf: (FilePath, FilePath.Component)? {
		guard self.components.count > 0 else { return nil }
		return (self.removingLastComponent(), self.lastComponent!)
	}
}

public extension FilesystemInterface {
	var rootDir: Dir {
		get throws {
			try self.dir(at: "/")
		}
	}
}
