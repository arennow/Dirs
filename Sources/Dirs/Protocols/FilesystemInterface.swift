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

public protocol FilesystemInterface {
	func nodeType(at ifp: some IntoFilePath) -> NodeType?

	func contentsOf(file ifp: some IntoFilePath) throws -> Data
	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat>
}

struct RealFSInterface: FilesystemInterface {
	func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		var isDirectory: ObjCBool = false

		if FileManager.default.fileExists(atPath: ifp.into().string, isDirectory: &isDirectory) {
			return isDirectory.boolValue ? .dir : .file
		} else {
			return nil
		}
	}

	func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		try Data(contentsOf: ifp.into().url)
	}

	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		try FileManager.default.contentsOfDirectory(at: ifp.into().url,
													includingPropertiesForKeys: [.isDirectoryKey])
			.map { FilePathStat(filePath: FilePath($0.path),
								isDirectory: try $0.getBoolResourceValue(forKey: .isDirectoryKey)) }
	}
}
