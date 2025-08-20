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
		let resolvedPathString = try realpath(rawPathString)

		self.chroot = FilePath(resolvedPathString)
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		let attrs = try? FileManager.default.attributesOfItem(atPath: self.resolveToRaw(ifp).string)

		switch attrs?[.type] as? FileAttributeType {
			case .typeDirectory: return .dir
			case .typeSymbolicLink: return .symlink
			case .none: return nil
			default: return .file
		}
	}

	public func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType? {
		let fp = self.resolveToRaw(ifp)

		do {
			let followedPath = try FileManager.default.destinationOfSymbolicLink(atPath: fp.string)
			return self.nodeType(at: followedPath)
		} catch {
			return self.nodeType(at: fp)
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		try Data(contentsOf: self.resolveToRaw(ifp))
	}

	public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		let fp = ifp.into()
		let unfurledFP = (try? self.destinationOf(symlink: fp)) ?? fp
		let unfurledURL = URL(fileURLWithPath: self.resolveToRaw(unfurledFP).string)

		let fm = FileManager.default

		return try fm.contentsOfDirectory(at: unfurledURL,
										  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			.map { rawURL in
				var chrootRelativeFilePath = FilePath(rawURL.path)
				if let chroot = self.chroot {
					let didRemove = chrootRelativeFilePath.removePrefix(chroot)
					precondition(didRemove)
					// removing the prefix also turns this into a relative path so:
					chrootRelativeFilePath.root = "/"
				}

				let isDir: Bool
				if try rawURL.getBoolResourceValue(forKey: .isSymbolicLinkKey) {
					var isDirObjCBool: ObjCBool = false
					_ = fm.fileExists(atPath: rawURL.path, isDirectory: &isDirObjCBool)
					isDir = isDirObjCBool.boolValue
				} else {
					isDir = try rawURL.getBoolResourceValue(forKey: .isDirectoryKey)
				}

				return FilePathStat(filePath: chrootRelativeFilePath, isDirectory: isDir)
			}
	}

	public func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath {
		let rawPathString = try FileManager.default.destinationOfSymbolicLink(atPath: self.resolveToRaw(ifp).string)
		let projected = self.resolveToProjected(rawPathString)
		return projected
	}

	public func realpathOf(node ifp: some IntoFilePath) throws -> FilePath {
		let out = try realpath(self.resolveToRaw(ifp).string)
		return self.resolveToProjected(out)
	}

	/// - Warning: When there's a `chroot`, this will create an alternate universe version of a
	///            system-provided path
	public func lookUpDir(_ dlk: DirLookupKind) throws -> Dir {
		let url: URL

		if dlk == .uniqueTemporary {
			var temp = NSTemporaryDirectory()
			temp.append("/temporary_\(UUID().uuidString)")
			url = temp.into()
		} else if dlk == .temporary {
			url = NSTemporaryDirectory().into()
		} else {
			let fmSearchPath: FileManager.SearchPathDirectory = switch dlk {
				case .documents: .documentDirectory
				case .cache: .cachesDirectory
				case .temporary, .uniqueTemporary: preconditionFailure("Shouldn't be reachable")
			}

			guard let innerURL = FileManager.default.urls(for: fmSearchPath, in: .userDomainMask).first else {
				throw DirLookupFailed(kind: dlk)
			}
			url = innerURL
		}

		return try Dir(fs: self, path: self.resolveToProjected(url), createIfNeeded: true)
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

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		try FileManager.default.createSymbolicLink(at: self.resolveToRaw(linkIFP),
												   withDestinationURL: self.resolveToRaw(destIFP))
		return try Symlink(fs: self, path: self.resolveToProjected(linkIFP))
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		let fd = try FileDescriptor.open(self.resolveToRaw(ifp), .writeOnly, retryOnInterrupt: true)
		defer { try? fd.close() }
		let data = contents.into()
		try fd.writeAll(data)
		try fd.resize(to: numericCast(data.count))
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fd = try FileDescriptor.open(self.resolveToRaw(ifp), .writeOnly, options: .append, retryOnInterrupt: true)
		defer { try? fd.close() }
		try fd.writeAll(addendum.into())
	}

	public func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws {
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

		try fm.copyItem(at: srcURL, to: destURL)
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		try FileManager.default.removeItem(at: self.resolveToRaw(ifp))
	}

	@discardableResult
	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws -> FilePath {
		var destURL: URL = self.resolveToRaw(destination)
		let srcURL: URL = self.resolveToRaw(source)
		let fm = FileManager.default

		var isDirectory: ObjCBool = false
		if fm.fileExists(atPath: destURL.pathNonPercentEncoded(), isDirectory: &isDirectory),
		   isDirectory.boolValue
		{
			destURL.appendPathComponent(srcURL.lastPathComponent)
		} else {
			do {
				try fm.removeItem(at: destURL)
			} catch {
				/*
				 `fileExists` resolves symlinks, meaning it returns `false` for
				 broken symlinks, but `moveItem` still fails because the symlink
				 does actually exist. So we just try to delete any non-directory
				 destination
				 So if deletion fails because the file doesn't exist, we swallow it
				 */
				let nse = error as NSError
				if nse.domain == NSCocoaErrorDomain, nse.code == CocoaError.fileNoSuchFile.rawValue {
					// nbd
				} else {
					throw error
				}
			}
		}

		try fm.moveItem(at: srcURL, to: destURL)
		return self.resolveToProjected(destURL)
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

private func realpath(_ path: String) throws -> String {
	guard let resolvedCPathString = realpath(path, nil) else {
		throw InvalidPathForCall.couldNotCanonicalize(path)
	}
	defer { free(resolvedCPathString) }
	let resolvedPathString = String(cString: resolvedCPathString)

	return resolvedPathString
}
