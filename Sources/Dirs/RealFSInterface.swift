import Foundation
import SystemPackage

#if canImport(Darwin)
	import Darwin
#elseif os(Linux)
	import Glibc

	// Additional Linux C imports in LinuxCImports.swift
#endif

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

	#if canImport(Darwin) || os(Linux)
		public func extendedAttributeNames(at ifp: some IntoFilePath) throws -> Set<String> {
			let fp = ifp.into()
			let path = self.resolveToRaw(fp).string

			let bufferSize = try xattrCall(attributeName: nil, path: fp) {
				#if canImport(Darwin)
					listxattr(path, nil, 0, XATTR_NOFOLLOW)
				#elseif os(Linux)
					llistxattr(path, nil, 0)
				#endif
			}

			guard bufferSize > 0 else {
				return []
			}

			return try withUnsafeTemporaryAllocation(of: CChar.self, capacity: bufferSize) { buffer in
				let actualSize = try xattrCall(attributeName: nil, path: fp) {
					#if canImport(Darwin)
						listxattr(path, buffer.baseAddress, bufferSize, XATTR_NOFOLLOW)
					#elseif os(Linux)
						llistxattr(path, buffer.baseAddress, bufferSize)
					#endif
				}

				// Parse null-terminated strings from buffer
				var names = Set<String>()
				var currentStart = 0
				for i in 0..<actualSize {
					if buffer[i] == 0 {
						if currentStart < i {
							if let name = String(validatingCString: buffer.baseAddress! + currentStart) {
								names.insert(name)
							}
						}
						currentStart = i + 1
					}
				}

				return names
			}
		}

		public func extendedAttribute(named name: String, at ifp: some IntoFilePath) throws -> Data? {
			let fp = ifp.into()
			let path = self.resolveToRaw(fp).string

			do {
				let bufferSize = try xattrCall(attributeName: name, path: fp) {
					#if canImport(Darwin)
						getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
					#elseif os(Linux)
						lgetxattr(path, name, nil, 0)
					#endif
				}

				guard bufferSize > 0 else {
					return Data()
				}

				return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: bufferSize) { buffer in
					let actualSize = try xattrCall(attributeName: name, path: fp) {
						#if canImport(Darwin)
							getxattr(path, name, buffer.baseAddress, bufferSize, 0, XATTR_NOFOLLOW)
						#elseif os(Linux)
							lgetxattr(path, name, buffer.baseAddress, bufferSize)
						#endif
					}

					return Data(bytes: buffer.baseAddress!, count: actualSize)
				}
			} catch is XAttrNotFound {
				return nil
			}
		}

		public func setExtendedAttribute(named name: String, to value: Data, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()
			let path = self.resolveToRaw(fp).string

			try value.withUnsafeBytes { bufferPointer in
				_ = try xattrCall(attributeName: name, path: fp) {
					#if canImport(Darwin)
						setxattr(path, name, bufferPointer.baseAddress, value.count, 0, XATTR_NOFOLLOW)
					#elseif os(Linux)
						lsetxattr(path, name, bufferPointer.baseAddress, value.count, 0)
					#endif
				}
			}
		}

		public func removeExtendedAttribute(named name: String, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()
			let path = self.resolveToRaw(fp).string

			do {
				_ = try xattrCall(attributeName: name, path: fp) {
					#if canImport(Darwin)
						removexattr(path, name, XATTR_NOFOLLOW)
					#elseif os(Linux)
						lremovexattr(path, name)
					#endif
				}
			} catch is XAttrNotFound {
				// Silently succeed if attribute doesn't exist
				return
			}
		}
	#endif
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

#if canImport(Darwin) || os(Linux)
	#if os(Linux)
		// Linux VFS limit for extended attribute names (see xattr(7) man page)
		private let XATTR_MAXNAMELEN = 255
	#endif

	@discardableResult
	private func xattrCall<T: BinaryInteger>(attributeName: String?,
											 path: FilePath,
											 _ call: () -> T) throws -> T
	{
		let result = call()
		guard result != -1 else {
			throw makeXattrError(errno: errno, attributeName: attributeName, path: path)
		}
		return result
	}

	private func makeXattrError(errno: Int32, attributeName: String?, path: FilePath) -> any Error {
		#if canImport(Darwin)
			let notFoundErrno = ENOATTR
			let notSupportedErrno = ENOTSUP
		#elseif os(Linux)
			let notFoundErrno = ENODATA
			let notSupportedErrno = EOPNOTSUPP
		#endif

		if errno == notFoundErrno {
			return XAttrNotFound()
		}

		// These errno values can only occur during operations on a specific attribute
		var requiredAttributeName: String {
			assert(attributeName != nil, "attributeName required for this errno")
			return attributeName ?? ":unspecified:"
		}

		switch errno {
			case notSupportedErrno:
				return XAttrNotSupported(path: path)
			case ENAMETOOLONG:
				return XAttrNameTooLong(attributeName: requiredAttributeName, path: path)
			case E2BIG:
				return XAttrValueTooLarge(attributeName: requiredAttributeName, path: path)
			case ERANGE:
				#if os(Linux)
					// On Linux, ERANGE can mean either:
					// 1. Attribute name too long (>255 bytes)
					// 2. Buffer provided for reading is too small for the attribute value
					// Check name length to determine which case applies
					if let name = attributeName, name.utf8.count > XATTR_MAXNAMELEN {
						return XAttrNameTooLong(attributeName: requiredAttributeName, path: path)
					}
				#endif
				return XAttrBufferTooSmall(attributeName: requiredAttributeName, path: path)
			case ENOSPC:
				return XAttrNoSpace(attributeName: requiredAttributeName, path: path)
			default:
				return NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
	}
#endif
