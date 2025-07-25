import Foundation
import SystemPackage

public struct FilePathStat: Hashable, Equatable {
	public let filePath: FilePath
	public let isDirectory: Bool

	public init(filePath: FilePath, isDirectory: Bool) {
		self.filePath = filePath
		self.isDirectory = isDirectory
	}
}

public enum NodeType: Sendable {
	case dir, file, symlink
}

public enum DirLookupKind: String, Sendable {
	case documents, cache, temporary
	case uniqueTemporary
}

public protocol FilesystemInterface: Equatable, Sendable {
	func nodeType(at ifp: some IntoFilePath) -> NodeType?
	func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType?

	func contentsOf(file ifp: some IntoFilePath) throws -> Data
	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat>
	func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath
	func realpathOf(node ifp: some IntoFilePath) throws -> FilePath

	func lookUpDir(_ dlk: DirLookupKind) throws -> Dir

	@discardableResult
	func createFile(at ifp: some IntoFilePath) throws -> File
	@discardableResult
	func createDir(at ifp: some IntoFilePath) throws -> Dir
	@discardableResult
	func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink

	func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws
	func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws

	func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws
	func deleteNode(at ifp: some IntoFilePath) throws
	@discardableResult
	func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws -> FilePath
}

public extension FilesystemInterface {
	@discardableResult
	func renameNode(at source: some IntoFilePath, to newName: String) throws -> FilePath {
		if newName.contains("/") {
			throw InvalidPathForCall.needSingleComponent
		}

		let sourceFP = source.into()
		let destPath = sourceFP.removingLastComponent().appending(newName)
		if let existingNT = self.nodeType(at: destPath) {
			throw NodeAlreadyExists(path: destPath, type: existingNT)
		}
		return try self.moveNode(from: sourceFP, to: destPath)
	}
}

public extension FilesystemInterface {
	func dir(at ifp: some IntoFilePath) throws -> Dir {
		try Dir(fs: self, path: ifp.into())
	}

	func file(at ifp: some IntoFilePath) throws -> File {
		try File(fs: self, path: ifp.into())
	}

	@discardableResult
	func createFileAndIntermediaryDirs(at ifp: some IntoFilePath) throws -> File {
		guard let (path, leaf) = ifp.into().pathAndLeaf else {
			throw InvalidPathForCall.needAbsoluteWithComponent
		}

		let dir = try self.rootDir.createDir(at: path)
		let file = try dir.createFile(at: leaf)
		return file
	}
}

public extension FilesystemInterface {
	func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fp = ifp.into()
		var content = (try? self.contentsOf(file: fp)) ?? Data()
		content.append(addendum.into())
		try self.replaceContentsOfFile(at: fp, to: content)
	}
}

extension FilePath {
	var pathAndLeaf: (FilePath, FilePath.Component)? {
		guard self.components.count > 0 else { return nil }
		return (self.removingLastComponent(), self.lastComponent!)
	}
}

public extension FilesystemInterface {
	func isEqual(to other: any FilesystemInterface) -> Bool {
		guard let other = other as? Self else { return false }
		return self == other
	}

	var rootDir: Dir {
		get throws {
			try self.dir(at: "/")
		}
	}
}
