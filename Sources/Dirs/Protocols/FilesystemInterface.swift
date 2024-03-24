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

	func createDir(at fp: FilePath) throws -> Dir
}
