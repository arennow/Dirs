import Foundation
import SystemPackage

public struct RealFSInterface: FilesystemInterface {
	public let chroot: FilePath?

	public init(chroot: FilePath? = nil) {
		self.chroot = chroot
	}

	public init(chroot: ChrootDirectory) throws {
		let rawPathString = chroot.path.string
		try FileManager.default.createDirectory(atPath: rawPathString,
												withIntermediateDirectories: true)
		guard let resolvedCPathString = realpath(rawPathString, nil) else {
			throw InvalidPathForCall.couldNotCanonicalize(rawPathString)
		}
		defer { free(resolvedCPathString) }
		let resolvedPathString = String(cString: resolvedCPathString)

		self.chroot = FilePath(resolvedPathString)
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		var isDirectory: ObjCBool = false

		if FileManager.default.fileExists(atPath: self.resolveToRaw(ifp).string, isDirectory: &isDirectory) {
			return isDirectory.boolValue ? .dir : .file
		} else {
			return nil
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		try Data(contentsOf: self.resolveToRaw(ifp))
	}

	public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		try FileManager.default.contentsOfDirectory(at: self.resolveToRaw(ifp),
													includingPropertiesForKeys: [.isDirectoryKey])
			.map { rawURL in
				var chrootRelativeFilePath = FilePath(rawURL.path)
				if let chroot = self.chroot {
					precondition(chrootRelativeFilePath.removePrefix(chroot))
					// removing the prefix also turns this into a relative path so:
					chrootRelativeFilePath.root = "/"
				}

				return FilePathStat(filePath: chrootRelativeFilePath,
									isDirectory: try rawURL.getBoolResourceValue(forKey: .isDirectoryKey))
			}
	}

	public func filePathOfNonexistentTemporaryFile(extension: String?) -> SystemPackage.FilePath {
		var filename = UUID().uuidString
		if let `extension` {
			filename += ".\(`extension`.trimmingCharacters(in: ["."]))"
		}

		return FileManager.default.temporaryDirectory.appendingPathComponent(filename).into()
	}

	public func createFile(at ifp: some IntoFilePath) throws -> File {
		try Data().write(to: self.resolveToRaw(ifp), options: .withoutOverwriting)
		return try File(fs: self, path: self.resolveToProjected(ifp))
	}

	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		try FileManager.default.createDirectory(at: self.resolveToRaw(ifp),
												withIntermediateDirectories: true)
		return try Dir(fs: self, path: self.resolveToProjected(ifp))
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		try contents.into().write(to: self.resolveToRaw(ifp), options: .atomic)
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fd = try FileDescriptor.open(self.resolveToRaw(ifp), .writeOnly, options: .append, retryOnInterrupt: true)
		defer { try? fd.close() }
		try fd.writeAll(addendum.into())
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		try FileManager.default.removeItem(at: self.resolveToRaw(ifp))
	}

	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws {
		var destURL: URL = self.resolveToRaw(destination)
		let srcURL: URL = self.resolveToRaw(source)
		let fm = FileManager.default

		var isDirectory: ObjCBool = false
		if fm.fileExists(atPath: destURL.pathNonPercentEncoded(), isDirectory: &isDirectory) {
			if isDirectory.boolValue {
				destURL.appendPathComponent(srcURL.lastPathComponent)
			} else {
				try fm.removeItem(at: destURL)
			}
		}

		try fm.moveItem(at: srcURL, to: destURL)
	}
}

public extension RealFSInterface {
	struct ChrootDirectory {
		public static func temporaryUnique() -> Self {
			self.init(path: FilePath(NSTemporaryDirectory() + UUID().uuidString))
		}

		public let path: FilePath
	}
}

private extension RealFSInterface {
	func resolveToProjected(_ ifp: some IntoFilePath) -> FilePath {
		var fp = ifp.into()
		guard let chroot = self.chroot else {
			return fp
		}

		if fp.removePrefix(chroot) {
			fp.root = "/"
		}
		return fp
	}

	func resolveToRaw(_ ifp: some IntoFilePath) -> FilePath {
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
	func resolveToRaw(_ ifp: some IntoFilePath) -> URL {
		(self.resolveToRaw(ifp) as FilePath).url
	}
}
