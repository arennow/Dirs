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

		self.init(chroot: FilePath(resolvedPathString))
	}

	#if canImport(Darwin)
		public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
			do {
				let fp: FilePath = self.resolveToRaw(ifp)
				// First, try the fast `getattrlist` method
				return try Self.classifyPathKind_getattrlist(fp)
			} catch POSIXError.ENOTDIR, POSIXError.ENOENT {
				// These mean the path doesn't exist
				return nil
			} catch {
				// For any other kind of error, including `NoFinderInfoAvailable`,
				// fall back to slower Foundation mechanisms
				do {
					let url: URL = self.resolveToRaw(ifp)
					let rv = try url.resourceValues(forKeys: [.fileResourceTypeKey, .isAliasFileKey])
					switch rv.fileResourceType {
						case .directory: return .dir
						case .symbolicLink: return .symlink
						case .regular:
							if rv.isAliasFile == true { return .finderAlias }
							return .file
						default:
							return .special
					}
				} catch {
					return nil
				}
			}
		}
	#else
		public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
			let url: URL = self.resolveToRaw(ifp)
			let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
			switch attrs?[.type] as? FileAttributeType {
				case .typeDirectory: return .dir
				case .typeSymbolicLink: return .symlink
				case .typeRegular: return .file
				case .none: return nil
				default: return .special
			}
		}
	#endif

	public func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType? {
		let fp = ifp.into()

		do {
			let resolvedPath = try self.realpathOf(node: fp)
			return self.nodeType(at: resolvedPath)
		} catch {
			return nil
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		let fp = ifp.into()
		let nodeType = self.nodeTypeFollowingSymlinks(at: fp)

		guard nodeType == .file else {
			if let nt = nodeType {
				throw WrongNodeType(path: fp, actualType: nt)
			} else {
				throw NoSuchNode(path: fp)
			}
		}

		return try Data(contentsOf: self.resolveToRaw(ifp))
	}

	public func sizeOfFile(at ifp: some IntoFilePath) throws -> UInt64 {
		let fp = ifp.into()
		let (resolvedPath, nodeType) = try self.resolveSymlinksAndGetNodeType(at: fp)

		guard nodeType == .file else {
			throw WrongNodeType(path: fp, actualType: nodeType)
		}

		let url = URL(fileURLWithPath: self.resolveToRaw(resolvedPath).string)
		let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
		return UInt64(size)
	}

	public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
		let requestedPath = ifp.into()
		let (resolvedPath, _) = try self.resolveSymlinksAndGetNodeType(at: requestedPath)
		let rawURL = URL(fileURLWithPath: self.resolveToRaw(resolvedPath).string)

		let fm = FileManager.default

		var prefetchKeys: Array<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

		#if canImport(Darwin)
			prefetchKeys.append(contentsOf: [.isAliasFileKey, .fileResourceTypeKey])
		#endif

		return try fm.contentsOfDirectory(at: rawURL, includingPropertiesForKeys: prefetchKeys)
			.map { rawURL in
				var chrootRelativeFilePath = FilePath(rawURL.path)
				if let chroot = self.chroot {
					let didRemove = chrootRelativeFilePath.removePrefix(chroot)
					precondition(didRemove)
					// removing the prefix also turns this into a relative path so:
					chrootRelativeFilePath.root = "/"
				}

				// If the requested path differs from the resolved path (i.e., we followed symlinks),
				// replace the resolved path prefix with the requested path prefix
				if requestedPath != resolvedPath {
					let didRemove = chrootRelativeFilePath.removePrefix(resolvedPath)
					precondition(didRemove)
					chrootRelativeFilePath = requestedPath.appending(chrootRelativeFilePath.components)
				}

				let nodeType: NodeType
				if try rawURL.getBoolResourceValue(forKey: .isSymbolicLinkKey) {
					nodeType = .symlink
				} else if try rawURL.getBoolResourceValue(forKey: .isDirectoryKey) {
					nodeType = .dir
				} else {
					#if canImport(Darwin)
						if try rawURL.getBoolResourceValue(forKey: .isAliasFileKey) {
							nodeType = .finderAlias
						} else {
							let resourceType = try rawURL.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType
							if resourceType == .regular {
								nodeType = .file
							} else {
								nodeType = .special
							}
						}
					#else
						// On Linux, isAliasFileKey exists but throws NoResourceAvailable when accessed,
						// so we skip checking it entirely. Also, resourceValues doesn't return
						// fileResourceType for special files, so we use attributesOfItem to detect them.
						let attrs = try? FileManager.default.attributesOfItem(atPath: rawURL.path)
						let fileType = attrs?[.type] as? FileAttributeType
						if fileType == .typeRegular {
							nodeType = .file
						} else {
							nodeType = .special
						}
					#endif
				}

				return FilePathStat(filePath: chrootRelativeFilePath, nodeType: nodeType)
			}
	}

	public func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath {
		let rawPathString = try FileManager.default.destinationOfSymbolicLink(atPath: self.resolveToRaw(ifp).string)
		return self.resolveToProjected(rawPathString)
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
		} else if dlk == .home {
			url = FileManager.default.homeDirectoryForCurrentUser
		} else {
			let fmSearchPath: FileManager.SearchPathDirectory = switch dlk {
				case .downloads: .downloadsDirectory
				case .documents: .documentDirectory
				case .cache: .cachesDirectory
				case .home, .temporary, .uniqueTemporary: preconditionFailure("Shouldn't be reachable")
			}

			guard let innerURL = FileManager.default.urls(for: fmSearchPath, in: .userDomainMask).first else {
				throw DirLookupFailed(kind: dlk)
			}
			url = innerURL
		}

		return try Dir(_fs: self.asInterface, path: self.resolveToProjected(url), createIfNeeded: true)
	}

	public func createFile(at ifp: some IntoFilePath) throws -> File {
		try self.createNode(at: ifp, factory: File.init) { fp in
			try Data().write(to: self.resolveToRaw(fp), options: .withoutOverwriting)
		}
	}

	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		try self.createNode(at: ifp, factory: { try Dir(_fs: $0, path: $1) }) { fp in
			try FileManager.default.createDirectory(at: self.resolveToRaw(fp),
													withIntermediateDirectories: true)
		}
	}

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		try self.createNode(at: linkIFP, factory: Symlink.init) { linkFP in
			try FileManager.default.createSymbolicLink(at: self.resolveToRaw(linkFP),
													   withDestinationURL: self.resolveToRaw(destIFP))
		}
	}

	private func createNode<N>(at ifp: some IntoFilePath,
							   factory: (FSInterface, FilePath) throws -> N,
							   perform: (_ resolvedPath: FilePath) throws -> Void) throws -> N
	{
		let fp = ifp.into()

		if let existingType = self.nodeType(at: fp) {
			throw NodeAlreadyExists(path: fp, type: existingType)
		}
		try perform(fp)
		return try factory(self.asInterface, self.resolveToProjected(fp))
	}

	#if canImport(Darwin)
		public func createFinderAlias(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> FinderAlias {
			try self.createNode(at: linkIFP, factory: FinderAlias.init) { linkFP in
				let linkURL: URL = self.resolveToRaw(linkFP)
				let destURL: URL = self.resolveToRaw(destIFP)
				let bookmarkData = try destURL.bookmarkData(options: .suitableForBookmarkFile)
				try URL.writeBookmarkData(bookmarkData, to: linkURL)
			}
		}

		public func destinationOfFinderAlias(at ifp: some IntoFilePath) throws -> FilePath {
			let linkURL: URL = self.resolveToRaw(ifp)
			let resolvedURL = try URL(resolvingAliasFileAt: linkURL, options: [.withoutUI])
			return self.resolveToProjected(resolvedURL)
		}
	#endif

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		let fp = ifp.into()
		let nodeType = self.nodeTypeFollowingSymlinks(at: fp)

		guard nodeType == .file else {
			if let nt = nodeType {
				throw WrongNodeType(path: fp, actualType: nt)
			} else {
				throw NoSuchNode(path: fp)
			}
		}

		let fd = try FileDescriptor.open(self.resolveToRaw(ifp), .writeOnly, retryOnInterrupt: true)
		defer { try? fd.close() }
		let data = contents.into()
		try fd.writeAll(data)
		try fd.resize(to: numericCast(data.count))
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fp = ifp.into()
		let nodeType = self.nodeTypeFollowingSymlinks(at: fp)

		guard nodeType == .file else {
			if let nt = nodeType {
				throw WrongNodeType(path: fp, actualType: nt)
			} else {
				throw NoSuchNode(path: fp)
			}
		}

		let fd = try FileDescriptor.open(self.resolveToRaw(ifp), .writeOnly, options: .append, retryOnInterrupt: true)
		defer { try? fd.close() }
		try fd.writeAll(addendum.into())
	}

	public func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws {
		let srcFP = source.into()
		let destFP = destination.into()

		var destURL: URL = self.resolveToRaw(destFP)
		let srcURL: URL = self.resolveToRaw(srcFP)
		let fm = FileManager.default

		let destType = self.nodeType(at: destFP)
		switch destType {
			case .symlink:
				if let resolvedType = self.nodeTypeFollowingSymlinks(at: destFP), resolvedType == .dir {
					destURL.appendPathComponent(srcURL.lastPathComponent)
				} else {
					try fm.removeItem(at: destURL)
				}
			case .dir:
				destURL.appendPathComponent(srcURL.lastPathComponent)
			#if canImport(Darwin)
				case .finderAlias: fallthrough
			#endif
			case .file, .special:
				try fm.removeItem(at: destURL)
			case .none:
				break
		}

		try fm.copyItem(at: srcURL, to: destURL)

		#if !canImport(Darwin)
			// `FileManager.copyItem`` only preserves extended attributes on Darwin
			// (because it uses `copyfile` under the hood). On other platforms, we have to
			// copy them manually.
			let xattrNames = try self.extendedAttributeNames(at: srcFP)
			for name in xattrNames {
				if let value = try self.extendedAttribute(named: name, at: srcFP) {
					try self.setExtendedAttribute(named: name, to: value, at: FilePath(destURL.path))
				}
			}
		#endif
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
	/// Fully resolves all symlinks in the path and returns both the resolved path and node type.
	func resolveSymlinksAndGetNodeType(at ifp: some IntoFilePath) throws -> (resolvedPath: FilePath, nodeType: NodeType) {
		let fp = ifp.into()

		let resolvedFP = try self.realpathOf(node: fp)
		guard let nodeType = self.nodeType(at: resolvedFP) else {
			// This shouldn't happen since we just confirmed it exists, but handle it anyway
			throw NoSuchNode(path: fp)
		}

		return (resolvedFP, nodeType)
	}

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
		if errno == ENOENT {
			throw NoSuchNode(path: FilePath(path))
		} else {
			throw InvalidPathForCall.couldNotCanonicalize(path)
		}
	}
	defer { free(resolvedCPathString) }
	return String(cString: resolvedCPathString)
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
