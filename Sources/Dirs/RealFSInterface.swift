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

	#if DEBUG && FINDER_ALIASES_ENABLED
		/// When `true`, `nodeType(at:)` will act as if no FinderInfo is available
		public var forceMissingFinderInfo = false
	#endif

	public init(chroot: FilePath? = nil) {
		self.chroot = chroot
	}

	public init(chroot: ChrootDirectory) throws {
		let rawPathString = chroot.path.string
		try FileManager.default.createDirectory(atPath: rawPathString,
												withIntermediateDirectories: true)
		let resolvedPathString = try realpath(chroot.path, errorPathTransform: nil)

		self.init(chroot: FilePath(resolvedPathString))
	}

	// We only do this more complicated implementation if Finder aliases are enabled
	#if FINDER_ALIASES_ENABLED
		public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
			do {
				#if DEBUG
					if self.forceMissingFinderInfo {
						throw NoFinderInfoAvailable()
					}
				#endif

				let fp: FilePath = self.resolveToRaw(ifp)
				// First, try the fast `getattrlist` method
				return try Self.classifyPathKind_getattrlist(fp)
			} catch POSIXError.ENOTDIR, POSIXError.ENOENT {
				// These mean the path doesn't exist
				return nil
			} catch {
				// For any other kind of error, including `NoFinderInfoAvailable`,
				// fall back to slower Foundation mechanisms
				return Self.classifyPathKind_foundation(rawURL: self.resolveToRaw(ifp))
			}
		}
	#else // !FINDER_ALIASES_ENABLED
		public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
			let url: URL = self.resolveToRaw(ifp)
			let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
			switch attrs?[.type] as? FileAttributeType {
				case .typeDirectory: return .dir
				case .typeSymbolicLink: return .symlink
				case .typeRegular: return .file
				case .none: return nil
				#if os(Windows)
					default: return .file
				#else
					default: return .special
				#endif
			}
		}
	#endif

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		let fp = ifp.into()
		try self.throwIfBrokenSymlinkInExistingAncestors(of: fp)
		let (resolvedPath, nodeType) = try self.resolvedPathAndNodeType(of: fp)

		guard nodeType == .file else {
			throw WrongNodeType(path: fp, actualType: nodeType)
		}

		return try Data(contentsOf: self.resolveToRaw(resolvedPath))
	}

	public func sizeOfFile(at ifp: some IntoFilePath) throws -> UInt64 {
		let fp = ifp.into()
		try self.throwIfBrokenSymlinkInExistingAncestors(of: fp)
		let (resolvedPath, nodeType) = try self.resolvedPathAndNodeType(of: fp)

		guard nodeType == .file else {
			throw WrongNodeType(path: fp, actualType: nodeType)
		}

		let url = URL(fileURLWithPath: self.resolveToRaw(resolvedPath).string)
		let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
		return UInt64(size)
	}

	#if os(Windows)
		public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
			let requestedPath = ifp.into()
			let (resolvedPath, resolvedNodeType) = try self.resolvedPathAndNodeType(of: requestedPath)

			guard resolvedNodeType == .dir else {
				throw WrongNodeType(path: requestedPath, actualType: resolvedNodeType)
			}
			let rawPath = self.resolveToRaw(resolvedPath)

			let fm = FileManager.default

			let contents = try fm.contentsOfDirectory(atPath: rawPath.string)
			return contents.compactMap { name -> FilePathStat? in
				let entryPath = rawPath.appending(name)
				let entryPathString = entryPath.string

				var chrootRelativeFilePath = entryPath
				if let chroot = self.chroot {
					let didRemove = chrootRelativeFilePath.removePrefix(chroot)
					precondition(didRemove)
					chrootRelativeFilePath.root = "/"
				}

				if requestedPath != resolvedPath {
					let didRemove = chrootRelativeFilePath.removePrefix(resolvedPath)
					precondition(didRemove)
					chrootRelativeFilePath = requestedPath.appending(chrootRelativeFilePath.components)
				}

				let nodeType: NodeType
				if let attrs = try? fm.attributesOfItem(atPath: entryPathString),
				   let fileType = attrs[.type] as? FileAttributeType
				{
					if fileType == .typeSymbolicLink {
						nodeType = .symlink
					} else if fileType == .typeDirectory {
						nodeType = .dir
					} else {
						nodeType = .file
					}
				} else {
					if (try? fm.destinationOfSymbolicLink(atPath: entryPathString)) != nil {
						nodeType = .symlink
					} else {
						return nil
					}
				}

				return FilePathStat(filePath: chrootRelativeFilePath, nodeType: nodeType)
			}
		}
	#else // !os(Windows)
		public func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat> {
			let requestedPath = ifp.into()
			let (resolvedPath, resolvedNodeType) = try self.resolvedPathAndNodeType(of: requestedPath)

			guard resolvedNodeType == .dir else {
				throw WrongNodeType(path: requestedPath, actualType: resolvedNodeType)
			}

			#if FINDER_ALIASES_ENABLED
				// getattrlistbulk returns names + node types (+ whether FinderInfo was present)
				// in bulk kernel calls — unlike FileManager, it does not suppress ._-prefixed files.
				let rawPath: FilePath = self.resolveToRaw(resolvedPath)
				let rawEntries = try Self.contentsOfDirectory_getattrlistbulk(rawPath: rawPath)

				return rawEntries.compactMap { name, nodeTypeFromBulk in
					var childPath = self.resolveToProjected(rawPath.appending(name))
					if requestedPath != resolvedPath {
						let didRemove = childPath.removePrefix(resolvedPath)
						precondition(didRemove)
						childPath = requestedPath.appending(childPath.components)
					}

					// nodeTypeFromBulk is nil when the filesystem didn't return FNDRINFO for
					// this entry (e.g. SMB, FAT32) — we can't distinguish .file from .finderAlias
					// without a Foundation fallback. forceMissingFinderInfo (DEBUG only) forces
					// the same fallback for all entries to exercise that code path in tests.
					let needsFallback: Bool
					#if DEBUG
						needsFallback = nodeTypeFromBulk == nil || self.forceMissingFinderInfo
					#else
						needsFallback = nodeTypeFromBulk == nil
					#endif

					if needsFallback {
						// Go directly to Foundation rather than routing through nodeType(at:),
						// which would make a per-entry classifyPathKind_getattrlist call that is
						// guaranteed to find FNDRINFO absent for the same reason the bulk call did.
						guard let nodeType = Self.classifyPathKind_foundation(rawURL: self.resolveToRaw(childPath)) else {
							// If Foundation can't stat the entry at all, skip it (e.g. it was deleted after we read the directory but before we could stat it, or it's a weird special file that FinderInfo can classify but Foundation can't)
							return nil
						}
						return FilePathStat(filePath: childPath, nodeType: nodeType)
					} else {
						// Safe force-unwrap: needsFallback covers the nil case above.
						return FilePathStat(filePath: childPath, nodeType: nodeTypeFromBulk!)
					}
				}
			#else
				let rawURL: URL = self.resolveToRaw(resolvedPath)
				let fm = FileManager.default

				return try fm.contentsOfDirectory(at: rawURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
					.map { rawURL in
						var chrootRelativeFilePath = self.resolveToProjected(rawURL)

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
							// On Linux, `resourceValues` doesn't return `fileResourceType` for
							// special files, so we use `attributesOfItem` to detect them
							let attrs = try? FileManager.default.attributesOfItem(atPath: rawURL.path)
							let fileType = attrs?[.type] as? FileAttributeType
							nodeType = fileType == .typeRegular ? .file : .special
						}

						return FilePathStat(filePath: chrootRelativeFilePath, nodeType: nodeType)
					}
			#endif
		}
	#endif

	public func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath {
		let rawPathString = try FileManager.default.destinationOfSymbolicLink(atPath: self.resolveToRaw(ifp).string)
		let destination = FilePath(rawPathString)

		if destination.root != nil {
			return self.resolveToProjected(destination)
		} else {
			// Preserve relative path as-is
			return destination
		}
	}

	public func realpathOf(node ifp: some IntoFilePath) throws -> FilePath {
		let fp = ifp.into()
		let out = try realpath(self.resolveToRaw(fp), errorPathTransform: { rawPath in
			let projectedPath = self.resolveToProjected(rawPath)
			if let transformed = self.terminalPathAfterFollowingSymlinkChain(startingAt: projectedPath) {
				return transformed
			}
			return projectedPath
		})
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
			url = URL(fileURLWithPath: NSHomeDirectory())
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
		try self.createNode(at: ifp, resolveAncestorSymlinks: false, factory: { try Dir(_fs: $0, path: $1) }) { fp in
			try self.throwIfBrokenSymlinkInExistingAncestors(of: fp)
			do {
				return try FileManager.default.createDirectory(at: self.resolveToRaw(fp),
															   withIntermediateDirectories: true)
			} catch {
				let errorIsNonDirAncestor: Bool
				#if os(Windows)
					errorIsNonDirAncestor = error.matchesAny(.cocoa(.fileNoSuchFile))
				#else
					errorIsNonDirAncestor = error.matches(outer: .cocoa(.fileWriteUnknown), underlying: .posix(.ENOTDIR))
				#endif

				if errorIsNonDirAncestor {
					let errorPath: FilePath
					if let firstNDA = try self.firstNonDirAncestor(of: fp) {
						errorPath = firstNDA.path
					} else {
						assertionFailure("No non-dir ancestor despite error: \(error)")
						errorPath = fp
					}

					throw NodeAlreadyExists(path: errorPath, type: self.nodeType(at: fp) ?? .file)
				}

				throw error
			}
		}
	}

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		try self.createNode(at: linkIFP, factory: Symlink.init) { linkFP in
			let destination = destIFP.into()
			let destString: String
			if destination.root != nil {
				destString = self.resolveToRaw(destination).string
			} else {
				// Relative destination: use as-is
				destString = destination.string
			}
			try FileManager.default.createSymbolicLink(atPath: self.resolveToRaw(linkFP).string,
													   withDestinationPath: destString)
		}
	}

	private func createNode<N>(at ifp: some IntoFilePath,
							   resolveAncestorSymlinks shouldResolveAncestorSymlinks: Bool = true,
							   factory: (FSInterface, FilePath) throws -> N,
							   perform: (_ resolvedPath: FilePath) throws -> Void) throws -> N
	{
		let fp = ifp.into()
		let resolvedFP: FilePath = if shouldResolveAncestorSymlinks {
			try self.resolveAncestorSymlinks(of: fp)
		} else {
			fp
		}

		if let existingType = self.nodeType(at: resolvedFP) {
			throw NodeAlreadyExists(path: fp, type: existingType)
		}
		do {
			try self.mapBasicCocoaErrorsToDirsErrors {
				try perform(resolvedFP)
			}
		} catch is PermissionDenied {
			// Foundation reports the child path, not the non-writable parent dir
			throw PermissionDenied(path: fp.removingLastComponent())
		}
		return try factory(self.asInterface, self.resolveToProjected(fp))
	}

	#if FINDER_ALIASES_ENABLED
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
			do {
				let resolvedURL = try URL(resolvingAliasFileAt: linkURL, options: [.withoutUI, .withoutMounting])
				return self.resolveToProjected(resolvedURL)
			} catch let error as CocoaError {
				// Darwin throws `fileReadNoSuchFile` when the reference chain is circular,
				// and `fileNoSuchFile` when the target has been deleted
				if error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
					throw NoSuchNode(path: ifp)
				}
				throw error
			}
		}
	#endif

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		let fp = ifp.into()
		let ancestorResolvedFP = try self.resolveAncestorSymlinks(of: fp)
		let (resolvedFP, nodeType) = try self.resolvedPathAndNodeType(of: ancestorResolvedFP)

		guard nodeType == .file else {
			throw WrongNodeType(path: fp, actualType: nodeType)
		}

		let rawPath: FilePath = self.resolveToRaw(resolvedFP)
		let fd: FileDescriptor
		do {
			fd = try FileDescriptor.open(rawPath, .writeOnly, retryOnInterrupt: true)
		} catch let errno as Errno where errno == .permissionDenied {
			throw PermissionDenied(path: fp)
		}

		try fd.closeAfter {
			let data = contents.into()
			try fd.writeAll(data)
			try fd.resize(to: numericCast(data.count))
		}
	}

	public func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fp = ifp.into()
		try self.throwIfBrokenSymlinkInExistingAncestors(of: fp)
		let (resolvedFP, nodeType) = try self.resolvedPathAndNodeType(of: fp)

		guard nodeType == .file else {
			throw WrongNodeType(path: fp, actualType: nodeType)
		}

		let rawPath: FilePath = self.resolveToRaw(resolvedFP)
		let fd: FileDescriptor
		do {
			fd = try FileDescriptor.open(rawPath, .writeOnly, options: .append, retryOnInterrupt: true)
		} catch let errno as Errno where errno == .permissionDenied {
			throw PermissionDenied(path: fp)
		}

		try fd.closeAfter {
			_ = try fd.writeAll(addendum.into())
		}
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
				if let resolvedType = try? self.nodeTypeResolvingSymlinks(at: destFP), resolvedType == .dir {
					destURL.appendPathComponent(srcURL.lastPathComponent)
				} else {
					try fm.removeItem(at: destURL)
				}
			case .dir:
				destURL.appendPathComponent(srcURL.lastPathComponent)
			#if FINDER_ALIASES_ENABLED
				case .finderAlias: fallthrough
			#endif
			#if SPECIALS_ENABLED
				case .special: fallthrough
			#endif
			case .file:
				try fm.removeItem(at: destURL)
			case .none:
				break
		}

		do {
			try mapBasicCocoaErrorsToDirsErrors {
				try fm.copyItem(at: srcURL, to: destURL)
			}
		} catch is PermissionDenied {
			// Foundation reports the source path, not the non-writable dest parent dir
			throw PermissionDenied(path: self.resolveToProjected(destURL.deletingLastPathComponent()))
		}

		#if XATTRS_ENABLED && os(Linux)
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
		let fp = ifp.into()
		let resolvedFP = try self.resolveAncestorSymlinks(of: fp)

		do {
			try self.mapBasicCocoaErrorsToDirsErrors {
				try FileManager.default.removeItem(at: self.resolveToRaw(resolvedFP))
			}
		} catch is PermissionDenied {
			let parentRaw: FilePath = self.resolveToRaw(fp.removingLastComponent())
			if !Self.isWritablePath(parentRaw.string) {
				throw PermissionDenied(path: fp.removingLastComponent())
			}
			// Find the actual non-writable descendant dir
			let rawFP: FilePath = self.resolveToRaw(resolvedFP)
			if let enumerator = FileManager.default.enumerator(atPath: rawFP.string) {
				while let item = enumerator.nextObject() as? String {
					let itemRawPath = rawFP.appending(item)
					if !Self.isWritablePath(itemRawPath.string) {
						let itemProjected = fp.appending(item)
						throw PermissionDenied(path: itemProjected)
					}
				}
			}
			throw PermissionDenied(path: fp)
		} catch let noSuchNode as NoSuchNode {
			if noSuchNode.path == resolvedFP {
				throw NoSuchNode(path: fp)
			} else {
				throw noSuchNode
			}
		}
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
		}

		// Moving a node to its own path is a no-op.
		if destURL.pathNonPercentEncoded() == srcURL.pathNonPercentEncoded() {
			return self.resolveToProjected(destURL)
		}

		if !isDirectory.boolValue {
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

		do {
			try self.mapBasicCocoaErrorsToDirsErrors {
				try fm.moveItem(at: srcURL, to: destURL)
			}
		} catch is PermissionDenied {
			// Foundation always reports the source path regardless of which
			// parent dir was readonly, so we check both to find the right one
			let destParent = destURL.deletingLastPathComponent()
			if !Self.isWritablePath(destParent.path) {
				throw PermissionDenied(path: self.resolveToProjected(destParent))
			}
			let srcParent = srcURL.deletingLastPathComponent()
			throw PermissionDenied(path: self.resolveToProjected(srcParent))
		}
		return self.resolveToProjected(destURL)
	}

	public func date(of type: NodeDateType, at ifp: some IntoFilePath) throws -> Date? {
		let fp = ifp.into()
		let path = self.resolveToRaw(fp).string

		return try self.mapBasicCocoaErrorsToDirsErrors {
			let attrs = try FileManager.default.attributesOfItem(atPath: path)
			switch type {
				case .creation:
					return attrs[.creationDate] as? Date
				case .modification:
					return attrs[.modificationDate] as? Date
			}
		}
	}

	#if XATTRS_ENABLED
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

package extension RealFSInterface {
	func setWritableForTesting(at ifp: some IntoFilePath, writable: Bool) throws -> () -> Void {
		let fp = ifp.into()
		let rawPath: FilePath = self.resolveToRaw(fp)
		let pathString = rawPath.string

		#if os(Windows)
			return try Self.windowsSetWritable(pathString: pathString, writable: writable, originalPath: fp)
		#else
			var st = stat()
			guard stat(pathString, &st) == 0 else {
				throw NoSuchNode(path: fp)
			}
			let originalMode = st.st_mode

			let newMode: mode_t
			if writable {
				newMode = originalMode | 0o200
			} else {
				newMode = originalMode & ~0o222
			}
			guard chmod(pathString, newMode) == 0 else {
				throw NoSuchNode(path: fp)
			}

			return {
				_ = chmod(pathString, originalMode)
			}
		#endif
	}
}

private extension RealFSInterface {
	#if FINDER_ALIASES_ENABLED
		/// Classifies a node via Foundation's `resourceValues` API.
		///
		/// This is the fallback path used when `getattrlist`-based classification is unavailable
		/// (e.g. `NoFinderInfoAvailable`, `forceMissingFinderInfo`). Accepting an already-resolved
		/// raw `URL` avoids redundant path resolution by callers that already have one.
		///
		/// - Returns: The node type, or `nil` if Foundation could not stat the path at all.
		static func classifyPathKind_foundation(rawURL: URL) -> NodeType? {
			guard let rv = try? rawURL.resourceValues(forKeys: [.fileResourceTypeKey, .isAliasFileKey]) else {
				return nil
			}
			switch rv.fileResourceType {
				case .directory: return .dir
				case .symbolicLink: return .symlink
				case .regular: return rv.isAliasFile == true ? .finderAlias : .file
				default: return .special
			}
		}
	#endif

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

private extension RealFSInterface {
	func terminalPathAfterFollowingSymlinkChain(startingAt fp: FilePath) -> Optional<FilePath> {
		try? detectCircularResolvables { recordPathVisited in
			var current = fp

			while self.nodeType(at: current) == .symlink {
				try recordPathVisited(current)

				guard let destination = try? self.destinationOf(symlink: current) else {
					return current
				}

				current = Symlink.resolveDestination(destination, relativeTo: current)
			}

			return current
		}
	}

	func resolveAncestorSymlinks(of fp: FilePath) throws -> FilePath {
		guard let lastComponent = fp.lastComponent else {
			return fp
		}

		let parentFP = fp.removingLastComponent()
		let resolvedParentFP = try self.realpathOf(node: parentFP)
		return resolvedParentFP.appending(lastComponent)
	}

	func throwIfBrokenSymlinkInExistingAncestors(of fp: FilePath) throws {
		var cumulativeFP = FilePath(root: fp.root, [])
		for component in fp.components {
			cumulativeFP = cumulativeFP.appending(component)
			guard let nodeType = self.nodeType(at: cumulativeFP) else {
				break
			}

			if nodeType == .symlink {
				_ = try self.realpathOf(node: cumulativeFP)
			}
		}
	}

	func mapBasicCocoaErrorsToDirsErrors<R>(in operation: () throws -> R) throws -> R {
		do {
			return try operation()
		} catch {
			if error.matchesAny(.cocoa(.fileNoSuchFile), .cocoa(.fileReadNoSuchFile)) {
				if let rawStringPath = error.userInfo[NSFilePathErrorKey] as? String {
					let errorPath = self.resolveToProjected(rawStringPath)
					throw NoSuchNode(path: errorPath)
				}
			}

			if self.isPermissionDeniedError(error) {
				if let rawStringPath = error.userInfo[NSFilePathErrorKey] as? String {
					throw PermissionDenied(path: self.resolveToProjected(rawStringPath))
				}
				throw error
			}

			throw error
		}
	}

	#if !os(Windows)
		// The Windows implementation is crazy and is in RealFSInterface+WindowsReadonly.swift
		static func isWritablePath(_ path: String) -> Bool {
			FileManager.default.isWritableFile(atPath: path)
		}
	#endif

	func isPermissionDeniedError(_ error: any Error) -> Bool {
		if error.matchesAny(.cocoa(.fileWriteNoPermission), .posix(.EACCES)) {
			return true
		}
		if error.matches(outer: .cocoa(.fileWriteUnknown), underlying: .posix(.EACCES)) {
			return true
		}
		if error.matches(outer: .cocoa(.fileWriteNoPermission), underlying: .posix(.EACCES)) {
			return true
		}
		if error.matches(outer: .cocoa(.fileReadNoPermission), underlying: .posix(.EACCES)) {
			return true
		}
		return false
	}

	func firstNonDirAncestor(of fp: FilePath) throws -> Optional<any Node> {
		let ancestorSequence: some Sequence<FilePath> = sequence(state: fp) { fp in
			guard fp.components.isEmpty == false else { return nil }
			fp.removeLastComponent()
			return fp
		}

		for ancestorFP in ancestorSequence {
			guard ancestorFP != fp else { continue }
			do {
				let node = try self.node(at: ancestorFP)
				if node.nodeType != .dir {
					return node
				}
			} catch is NoSuchNode {
				continue
			}
		}
		return nil
	}
}

#if os(Windows)
	import WinSDK

	private func realpath(_ path: FilePath, errorPathTransform: Optional<(FilePath) -> FilePath>) throws -> String {
		// 1) Make absolute (GetFullPathNameW)
		let fullPathW: [WCHAR] = try path.string.withCString(encodedAs: UTF16.self) { inW -> [WCHAR] in
			let needed = GetFullPathNameW(inW, 0, nil, nil)
			if needed == 0 {
				throw windowsRealpathError(path: path, errorPathTransform: errorPathTransform, win32Error: GetLastError())
			}

			var buf = Array<WCHAR>(repeating: 0, count: Int(needed) + 1)
			let written = GetFullPathNameW(inW, DWORD(buf.count), &buf, nil)
			if written == 0 {
				throw windowsRealpathError(path: path, errorPathTransform: errorPathTransform, win32Error: GetLastError())
			}

			// Ensure NUL-termination and trim to actual length.
			buf[Int(written)] = 0
			while buf.count > written + 1 {
				buf.removeLast()
			}
			return buf
		}

		// 2) Open a handle and ask Windows for the final resolved path
		let handle: HANDLE = fullPathW.withUnsafeBufferPointer { p -> HANDLE in
			// NOTE:
			// - FILE_FLAG_BACKUP_SEMANTICS is required for directories.
			// - Do NOT set FILE_FLAG_OPEN_REPARSE_POINT (we want to follow reparse points).
			CreateFileW(p.baseAddress!,
						DWORD(FILE_READ_ATTRIBUTES), // minimal access for metadata
						DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
						nil,
						DWORD(OPEN_EXISTING),
						DWORD(FILE_FLAG_BACKUP_SEMANTICS),
						nil)
		}

		if handle == INVALID_HANDLE_VALUE {
			throw windowsRealpathError(path: path, errorPathTransform: errorPathTransform, win32Error: GetLastError())
		}
		defer { CloseHandle(handle) }

		// GetFinalPathNameByHandleW returns things like:
		//   \\?\C:\...
		//   \\?\UNC\server\share\...
		let finalW: [WCHAR] = {
			let flags = DWORD(FILE_NAME_NORMALIZED | VOLUME_NAME_DOS)
			let needed = GetFinalPathNameByHandleW(handle, nil, 0, flags)
			if needed == 0 {
				return [] // handled below as error
			}

			var buf = Array<WCHAR>(repeating: 0, count: Int(needed) + 1)
			let written = GetFinalPathNameByHandleW(handle, &buf, DWORD(buf.count), flags)
			if written == 0 {
				return []
			}

			// Ensure NUL-termination and trim to actual length.
			buf[Int(written)] = 0
			while buf.count > written + 1 {
				buf.removeLast()
			}
			return buf
		}()

		if finalW.isEmpty {
			throw windowsRealpathError(path: path, errorPathTransform: errorPathTransform, win32Error: GetLastError())
		}

		var finalStr = finalW.withUnsafeBufferPointer { p in
			String(decodingCString: p.baseAddress!, as: UTF16.self)
		}

		// 3) Normalize away the Win32 extended-length prefix
		//    \\?\C:\foo  -> C:\foo
		//    \\?\UNC\a\b -> \\a\b
		if finalStr.hasPrefix(#"\\?\UNC\"#) {
			finalStr.removeFirst(#"\\?\UNC"#.count) // leaves "\server\share\..."
			finalStr = #"\"# + finalStr // make it "\\server\share\..."
		} else if finalStr.hasPrefix(#"\\?\"#) {
			finalStr.removeFirst(#"\\?\"#.count)
		}

		return finalStr
	}

	private func windowsRealpathError(path: FilePath, errorPathTransform: Optional<(FilePath) -> FilePath>, win32Error: DWORD) -> any Error {
		let projectedPath = errorPathTransform?(path) ?? path
		switch win32Error {
			case DWORD(ERROR_FILE_NOT_FOUND), DWORD(ERROR_PATH_NOT_FOUND):
				return NoSuchNode(path: projectedPath)
			case DWORD(ERROR_CANT_RESOLVE_FILENAME):
				return CircularResolvableChain(startPath: projectedPath)
			default:
				return InvalidPathForCall.couldNotCanonicalize(path)
		}
	}
#else // Non-Windows
	private func realpath(_ path: FilePath, errorPathTransform: Optional<(FilePath) -> FilePath>) throws -> String {
		let resolvedCPathString = realpath(path.string, nil)

		guard let resolvedCPathString else {
			let projectedPath = errorPathTransform?(path) ?? path

			if errno == ENOENT {
				throw NoSuchNode(path: projectedPath)
			} else if errno == ELOOP {
				throw CircularResolvableChain(startPath: projectedPath)
			} else {
				throw InvalidPathForCall.couldNotCanonicalize(path)
			}
		}

		defer { free(resolvedCPathString) }
		return String(cString: resolvedCPathString)
	}
#endif

#if XATTRS_ENABLED
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
		case EPERM:
				return XAttrNotAllowed(path: path)
		case EACCES:
				return PermissionDenied(path: path)
		default:
				return NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
		}
	}
#endif
