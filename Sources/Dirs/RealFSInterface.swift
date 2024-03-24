import Foundation
import SystemPackage

public struct RealFSInterface: FilesystemInterface {
	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		var isDirectory: ObjCBool = false

		if FileManager.default.fileExists(atPath: ifp.into().string, isDirectory: &isDirectory) {
			return isDirectory.boolValue ? .dir : .file
		} else {
			return nil
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		try Data(contentsOf: ifp.into().url)
	}

	public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		try FileManager.default.contentsOfDirectory(at: ifp.into().url,
													includingPropertiesForKeys: [.isDirectoryKey])
			.map { FilePathStat(filePath: FilePath($0.path),
								isDirectory: try $0.getBoolResourceValue(forKey: .isDirectoryKey)) }
	}
}
