import Foundation
import SystemPackage

public struct RealFSInterface: FilesystemInterface {
	public let chroot: FilePath?

	public init(chroot: FilePath? = nil) {
		self.chroot = chroot
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		var isDirectory: ObjCBool = false

		if FileManager.default.fileExists(atPath: self.resolve(ifp).string, isDirectory: &isDirectory) {
			return isDirectory.boolValue ? .dir : .file
		} else {
			return nil
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		try Data(contentsOf: self.resolve(ifp))
	}

	public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		try FileManager.default.contentsOfDirectory(at: self.resolve(ifp),
													includingPropertiesForKeys: [.isDirectoryKey])
			.map { FilePathStat(filePath: FilePath($0.path),
								isDirectory: try $0.getBoolResourceValue(forKey: .isDirectoryKey)) }
	}

	public func filePathOfNonexistentTemporaryFile(extension: String?) -> SystemPackage.FilePath {
		var filename = UUID().uuidString
		if let `extension` {
			filename += ".\(`extension`.trimmingCharacters(in: ["."]))"
		}

		return FileManager.default.temporaryDirectory.appendingPathComponent(filename).into()
	}

	public func createFile(at ifp: some IntoFilePath) throws -> File {
		let fp = self.resolve(ifp)
		try Data().write(to: fp.url)
		return try File(fs: self, path: fp)
	}

	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		let fp = self.resolve(ifp)
		try FileManager.default.createDirectory(at: fp.into(), withIntermediateDirectories: true)
		return try Dir(fs: self, path: fp)
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		try contents.into().write(to: self.resolve(ifp), options: .atomic)
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fd = try FileDescriptor.open(self.resolve(ifp), .writeOnly, options: .append, retryOnInterrupt: true)
		defer { try? fd.close() }
		try fd.writeAll(addendum.into())
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		try FileManager.default.removeItem(at: self.resolve(ifp))
	}

	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath, replacingExisting: Bool) throws {
		let destURL: URL = self.resolve(destination)
		let srcURL: URL = self.resolve(source)
		let fm = FileManager.default

		var isDirectory: ObjCBool = false
		if fm.fileExists(atPath: destURL.pathNonPercentEncoded(), isDirectory: &isDirectory), !isDirectory.boolValue {
			try fm.removeItem(at: destURL)
		}

		try fm.moveItem(at: srcURL, to: destURL)
	}
}

private extension RealFSInterface {
	func resolve(_ ifp: some IntoFilePath) -> FilePath {
		if let chroot = self.chroot {
			let fp = ifp.into()
			if fp.starts(with: chroot) {
				return fp
			} else {
				return chroot.appending(fp.components)
			}
		} else {
			return ifp.into()
		}
	}

	@_disfavoredOverload
	func resolve(_ ifp: some IntoFilePath) -> URL {
		(self.resolve(ifp) as FilePath).url
	}
}
