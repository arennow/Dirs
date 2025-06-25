import Foundation
import SystemPackage

public struct FilePathStat {
	public struct StatType: OptionSet, Sendable {
		public let rawValue: UInt8
		public init(rawValue: UInt8) { self.rawValue = rawValue }

		public static let isDirectory = Self(rawValue: 0b0000_0001)
		public static let isSymlink = Self(rawValue: 0b0000_0010)
	}

	public let filePath: FilePath
	public let statType: StatType
	public var isDirectory: Bool { self.statType.contains(.isDirectory) }

	@available(*, deprecated, message: "Use the `StatType` initializer instead.")
	public init(filePath: FilePath, isDirectory: Bool) {
		self.init(filePath: filePath, statType: .isDirectory)
	}

	public init(filePath: FilePath, statType: StatType) {
		self.filePath = filePath
		self.statType = statType
	}
}

public enum NodeType: Sendable {
	case dir, file, symlink
}

public protocol FilesystemInterface: Equatable, Sendable {
	func nodeType(at ifp: some IntoFilePath) -> NodeType?

	func contentsOf(file ifp: some IntoFilePath) throws -> Data
	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat>
	func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath

	func filePathOfNonexistentTemporaryFile(extension: String?) -> FilePath

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
	func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws
}

public extension FilesystemInterface {
	func filePathOfNonexistentTemporaryFile() -> FilePath {
		self.filePathOfNonexistentTemporaryFile(extension: nil)
	}

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
