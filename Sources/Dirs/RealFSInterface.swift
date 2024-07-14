import Foundation
import SystemPackage

public struct RealFSInterface: FilesystemInterface {
	public func isEqual(to otherFSI: any FilesystemInterface) -> Bool {
		// This type has no stored properties, so they're all the same
		otherFSI is RealFSInterface
	}

	public init() {}

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

	public func filePathOfNonexistantTemporaryFile(extension: String?) -> SystemPackage.FilePath {
		var filename = UUID().uuidString
		if let `extension` {
			filename += ".\(`extension`.trimmingCharacters(in: ["."]))"
		}

		return FileManager.default.temporaryDirectory.appendingPathComponent(filename).into()
	}

	public func createFile(at ifp: some IntoFilePath) throws -> File {
		let fp = ifp.into()
		FileManager.default.createFile(atPath: fp.string, contents: nil)
		return try File(fs: self, path: fp)
	}

	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		let fp = ifp.into()
		try FileManager.default.createDirectory(at: fp.into(), withIntermediateDirectories: true)
		return try Dir(fs: self, path: fp)
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		try contents.into().write(to: ifp.into(), options: .atomic)
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fd = try FileDescriptor.open(ifp.into(), .writeOnly, options: .append, retryOnInterrupt: true)
		defer { try? fd.close() }
		try fd.writeAll(addendum.into())
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		try FileManager.default.removeItem(at: ifp.into())
	}

	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath, replacingExisting: Bool) throws {
		let destURL: URL = destination.into()
		let srcURL: URL = source.into()
		let fm = FileManager.default

		var isDirectory: ObjCBool = false
		if fm.fileExists(atPath: destURL.pathNonPercentEncoded(), isDirectory: &isDirectory), !isDirectory.boolValue {
			try fm.removeItem(at: destURL)
		}

		try fm.moveItem(at: srcURL, to: destURL)
	}
}
