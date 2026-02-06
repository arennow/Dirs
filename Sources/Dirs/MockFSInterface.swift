import Foundation
import Locked
import SystemPackage

public final class MockFSInterface: FilesystemInterface {
	private enum MockNode: Equatable {
		case dir(xattrs: Dictionary<String, Data> = [:])
		case file(data: Data = Data(), xattrs: Dictionary<String, Data> = [:])
		case symlink(destination: FilePath, xattrs: Dictionary<String, Data> = [:])
		case special(xattrs: Dictionary<String, Data> = [:])
		#if FINDER_ALIASES_ENABLED
			case finderAlias(destination: FilePath, xattrs: Dictionary<String, Data> = [:])
		#endif

		var nodeType: NodeType {
			switch self {
				case .dir: .dir
				#if FINDER_ALIASES_ENABLED
					case .finderAlias: .finderAlias
				#endif
				case .file: .file
				case .symlink: .symlink
				case .special: .special
			}
		}

		var xattrs: Dictionary<String, Data> {
			get {
				switch self {
					case .dir(let xattrs),
						 .file(_, let xattrs),
						 .symlink(_, let xattrs),
						 .special(let xattrs):
						return xattrs
					#if FINDER_ALIASES_ENABLED
						case .finderAlias(_, let xattrs):
							return xattrs
					#endif
				}
			}
			set {
				switch self {
					case .dir:
						self = .dir(xattrs: newValue)
					case .file(let data, _):
						self = .file(data: data, xattrs: newValue)
					case .symlink(let destination, _):
						self = .symlink(destination: destination, xattrs: newValue)
					case .special:
						self = .special(xattrs: newValue)
					#if FINDER_ALIASES_ENABLED
						case .finderAlias(let destination, _):
							self = .finderAlias(destination: destination, xattrs: newValue)
					#endif
				}
			}
		}
	}

	private enum SymlinkResolutionBehavior {
		case resolve, dontResolve, resolveExceptFinal

		func properFilePath(for ifp: some IntoFilePath, in ptn: PTN) -> FilePath? {
			let fp = ifp.into()

			do {
				return switch self {
					case .resolve:
						try MockFSInterface.realpath(of: fp, in: ptn)
					case .resolveExceptFinal:
						try MockFSInterface.realpath(of: fp, in: ptn, exceptFinalComponent: true)
					case .dontResolve:
						fp
				}
			} catch {
				return nil
			}
		}
	}

	private typealias PTN = Dictionary<FilePath, MockNode>

	/// Default maximum extended attribute name length (127 bytes). This matches Darwin's
	/// limit, which is small compared to other platforms.
	public static let defaultMaxExtendedAttributeNameLength = 127

	public static func == (lhs: MockFSInterface, rhs: MockFSInterface) -> Bool {
		lhs.id == rhs.id
	}

	@available(*, deprecated, message: "Use init() instead")
	public static func empty() -> Self { Self() }

	// To allow us to avoid traversing our fake FS for deep equality
	private let id = UUID()
	private let pathsToNodes: Locked<PTN>

	/// Maximum length for extended attribute names enforced by this mock filesystem.
	/// Different platforms have different limits (e.g., macOS uses 127, Linux uses 255), and the
	/// real filesystem implementation will defer to the platform's native validation.
	public let maxExtendedAttributeNameLength: Int

	public init(maxExtendedAttributeNameLength: Int = MockFSInterface.defaultMaxExtendedAttributeNameLength) {
		self.maxExtendedAttributeNameLength = maxExtendedAttributeNameLength
		self.pathsToNodes = Locked(["/": .dir()])
	}

	private static func node(at ifp: some IntoFilePath, in ptn: PTN, symRes: SymlinkResolutionBehavior) -> MockNode? {
		if let properFP = symRes.properFilePath(for: ifp, in: ptn) {
			ptn[properFP]
		} else {
			nil
		}
	}

	private static func existingAncestorResolvedNode(at ifp: some IntoFilePath, in ptn: PTN) throws -> (node: MockNode, resolvedPath: FilePath) {
		let fp = ifp.into()
		let resolvedFP = try Self.resolveAncestorSymlinks(of: fp, in: ptn)
		guard let node = ptn[resolvedFP] else {
			throw NoSuchNode(path: fp)
		}
		return (node, resolvedFP)
	}

	private static func nodeType(at ifp: some IntoFilePath, in ptn: PTN, symRes: SymlinkResolutionBehavior) -> NodeType? {
		Self.node(at: ifp, in: ptn, symRes: symRes)?.nodeType
	}

	/// Like `realpath(3)`
	/// - Parameters:
	///   - ifp: The path to reify
	///   - exceptFinalComponent: Whether to leave the final component alone. This is useful for
	///     resolving nodes that are subdirectories of symlinks to directories. If that node is itself a
	///     symlink, you'll get the real path to the symlink itself
	///   - ptn: The `PTN` to consult
	/// - Returns: The reified path
	///
	/// - Warning: This function does not yet handle `~`, etc.
	private static func realpath(of ifp: some IntoFilePath, in ptn: PTN, exceptFinalComponent: Bool = false) throws -> FilePath {
		try detectCircularResolvables { recordPathVisited in
			try Self.realpathImpl(of: ifp.into(), in: ptn, exceptFinalComponent: exceptFinalComponent, recordPathVisited: recordPathVisited)
		}
	}

	private static func realpathImpl(of fp: FilePath, in ptn: PTN, exceptFinalComponent: Bool, recordPathVisited: (FilePath) throws -> Void) throws -> FilePath {
		var builtRealpathFPCV = FilePath.ComponentView()
		var builtRealpathFP: FilePath {
			FilePath(root: fp.root, builtRealpathFPCV)
		}
		let components = Array(fp.components)
		for (index, comp) in components.enumerated() {
			if comp == FilePath.Component(".") {
				continue
			} else if comp == FilePath.Component("..") {
				if !builtRealpathFPCV.isEmpty {
					builtRealpathFPCV.removeLast()
				}
				continue
			}

			builtRealpathFPCV.append(comp)

			let isLastComponent = index == components.count - 1
			if exceptFinalComponent, isLastComponent {
				break
			}

			switch ptn[builtRealpathFP] {
				case .symlink(let destination, _):
					try recordPathVisited(builtRealpathFP)
					// If the destination is relative, resolve it relative to the symlink's parent
					if destination.root == nil {
						builtRealpathFPCV.removeLast()
						builtRealpathFPCV.append(contentsOf: destination.components)
					} else {
						builtRealpathFPCV = .init(destination.components)
					}
				case nil: throw NoSuchNode(path: fp)
				default: break
			}
		}

		let outThis = builtRealpathFP
		if outThis != fp {
			return try Self.realpathImpl(of: outThis, in: ptn, exceptFinalComponent: exceptFinalComponent, recordPathVisited: recordPathVisited)
		} else {
			// Check if the current path is itself a symlink that points to itself or has already been visited
			if case .symlink = ptn[outThis] {
				try recordPathVisited(outThis)
			}
			return outThis
		}
	}

	/// Resolves symlinks in the ancestor directory path and returns the path with the resolved
	/// ancestors and the original final component. This is used for operations that need to be
	/// able to work on nodes inside symlinked directories.
	private static func resolveAncestorSymlinks(of ifp: some IntoFilePath, in ptn: PTN) throws -> FilePath {
		let fp = ifp.into()
		guard let lastComponent = fp.lastComponent else {
			// Root path has no parent to resolve
			return fp
		}
		let parentFP = fp.removingLastComponent()
		let resolvedParentFP = try Self.realpath(of: parentFP, in: ptn)
		return resolvedParentFP.appending(lastComponent)
	}

	private func node(at ifp: some IntoFilePath, symRes: SymlinkResolutionBehavior) -> MockNode? {
		self.pathsToNodes.read { ptn in
			Self.node(at: ifp, in: ptn, symRes: symRes)
		}
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		let node: MockNode?
		if let exact = self.node(at: ifp, symRes: .dontResolve) {
			node = exact
		} else {
			node = self.node(at: ifp, symRes: .resolveExceptFinal)
		}

		return node?.nodeType
	}

	public func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType? {
		self.node(at: ifp, symRes: .resolve)?.nodeType
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		let fp = ifp.into()

		switch self.node(at: fp, symRes: .resolve) {
			case .file(let data, _): return data
			case .symlink(let destination, _):
				let resolvedDestination = Symlink.resolveDestination(destination, relativeTo: fp)
				return try self.contentsOf(file: resolvedDestination)
			case .none: throw NoSuchNode(path: fp)
			case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
		}
	}

	public func contentsOf(directory ifp: some Dirs.IntoFilePath) throws -> Array<Dirs.FilePathStat> {
		let fp = ifp.into()
		return try self.contentsOf(directory: fp, requestedPath: fp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func contentsOf(directory ifp: some Dirs.IntoFilePath,
							requestedPath: FilePath,
							using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> Array<Dirs.FilePathStat>
	{
		let fp = try Self.resolveAncestorSymlinks(of: ifp, in: acquisitionLock.resource)

		switch acquisitionLock.resource[fp] {
			case .none: throw NoSuchNode(path: fp)
			case .symlink(let destination, _):
				let resolvedDestination = Symlink.resolveDestination(destination, relativeTo: fp)
				return try self.contentsOf(directory: resolvedDestination, requestedPath: requestedPath, using: acquisitionLock)
			case .dir: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
		}

		let childKeys = acquisitionLock.resource.keys
			.lazy
			.filter { $0.starts(with: fp) }
			.filter { $0 != fp } // This may only remove `/`
			.filter { $0.removingLastComponent() == fp }

		return childKeys.map { childFilePath in
			// Safe force-unwrap: childFilePath came from acquisitionLock.resource.keys
			// And we're still holding the lock
			let node = acquisitionLock.resource[childFilePath]!

			// If we followed symlinks (requestedPath != fp), replace the resolved path prefix
			// with the requested path prefix
			let finalPath: FilePath
			if requestedPath != fp {
				var relativePath = childFilePath
				let didRemove = relativePath.removePrefix(fp)
				precondition(didRemove)
				finalPath = requestedPath.appending(relativePath.components)
			} else {
				finalPath = childFilePath
			}

			return FilePathStat(filePath: finalPath, nodeType: node.nodeType)
		}
	}

	public func sizeOfFile(at ifp: some IntoFilePath) throws -> UInt64 {
		let fp = ifp.into()

		switch self.node(at: fp, symRes: .resolve) {
			case .file(let data, _): return UInt64(data.count)
			case .none: throw NoSuchNode(path: fp)
			case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
		}
	}

	public func destinationOf(symlink ifp: some Dirs.IntoFilePath) throws -> FilePath {
		try self.destinationOf(symlink: ifp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func destinationOf(symlink ifp: some Dirs.IntoFilePath, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath {
		let fp = try Self.resolveAncestorSymlinks(of: ifp, in: acquisitionLock.resource)

		switch acquisitionLock.resource[fp] {
			case .symlink(let destination, _): return destination
			case .none: throw NoSuchNode(path: fp)
			case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
		}
	}

	public func realpathOf(node ifp: some IntoFilePath) throws -> FilePath {
		try self.pathsToNodes.read { ptn in
			try Self.realpath(of: ifp, in: ptn)
		}
	}

	public func lookUpDir(_ dlk: DirLookupKind) throws -> Dir {
		let path = switch dlk {
			case .temporary: "/_temporary"
			case .uniqueTemporary: "/_temporary/\(UUID().uuidString)"
			case .home: "/Users/TestUser"
			case .downloads: "/Users/TestUser/Downloads"
			default: "/_system_\(dlk.rawValue)"
		}
		return try Dir(_fs: self.asInterface, path: path, createIfNeeded: true)
	}

	@discardableResult
	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		let fp = ifp.into()

		// Check if the final path is root – can't create root
		if fp.root != nil, fp.components.isEmpty {
			throw NodeAlreadyExists(path: fp, type: .dir)
		}

		let comps = fp.components
		let eachIndex = sequence(first: comps.startIndex) { ind in
			comps.index(ind, offsetBy: 1, limitedBy: comps.endIndex)
		}
		let cumulativeFilePaths = eachIndex.map { endIndex in
			FilePath(root: "/", fp.components[comps.startIndex..<endIndex])
		}

		try self.pathsToNodes.mutate { ptn in
			for cumulativeFP in cumulativeFilePaths {
				// Root path will have no last component, skip it
				guard cumulativeFP.lastComponent != nil else { continue }

				let resolvedDirFP = try Self.resolveAncestorSymlinks(of: cumulativeFP, in: ptn)
				let isFinalComponent = cumulativeFP == fp

				switch ptn[resolvedDirFP] {
					case .dir:
						if isFinalComponent {
							throw NodeAlreadyExists(path: cumulativeFP, type: .dir)
						}
					case .symlink(let destination, _):
						if isFinalComponent {
							throw NodeAlreadyExists(path: cumulativeFP, type: .symlink)
						}

						let resolvedDestination = Symlink.resolveDestination(destination, relativeTo: resolvedDirFP)
						guard Self.nodeType(at: resolvedDestination, in: ptn, symRes: .resolve) == .dir else {
							throw WrongNodeType(path: cumulativeFP, actualType: .symlink)
						}
					case .none:
						ptn[resolvedDirFP] = .dir()
					case .some(let x):
						throw NodeAlreadyExists(path: cumulativeFP, type: x.nodeType)
				}
			}
		}

		return try Dir(_fs: self.asInterface, path: fp)
	}

	private func createNode<N>(at ifp: some IntoFilePath,
							   factory: (FSInterface, FilePath) throws -> N,
							   insertNode: (_ pathsToNodes: inout PTN, _ resolvedPath: FilePath) throws -> Void) throws -> N
	{
		let fp = ifp.into()
		try self.pathsToNodes.mutate { ptn in
			let parentFP = fp.removingLastComponent()
			guard Self.nodeType(at: parentFP, in: ptn, symRes: .resolve) == .dir else {
				throw NoSuchNode(path: parentFP)
			}

			let resolvedFP = try Self.resolveAncestorSymlinks(of: fp, in: ptn)

			if let existing = ptn[resolvedFP] {
				throw NodeAlreadyExists(path: fp, type: existing.nodeType)
			}

			try insertNode(&ptn, resolvedFP)
		}
		return try factory(self.asInterface, fp)
	}

	@discardableResult
	public func createFile(at ifp: some IntoFilePath) throws -> File {
		try self.createNode(at: ifp, factory: File.init, insertNode: { ptn, resolvedFP in
			ptn[resolvedFP] = .file()
		})
	}

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		try self.createNode(at: linkIFP, factory: Symlink.init, insertNode: { ptn, resolvedFP in
			ptn[resolvedFP] = .symlink(destination: destIFP.into())
		})
	}

	#if FINDER_ALIASES_ENABLED
		public func createFinderAlias(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> FinderAlias {
			try self.createNode(at: linkIFP, factory: FinderAlias.init, insertNode: { ptn, resolvedFP in
				ptn[resolvedFP] = .finderAlias(destination: destIFP.into())
			})
		}

		public func destinationOfFinderAlias(at ifp: some Dirs.IntoFilePath) throws -> FilePath {
			try self.destinationOfFinderAlias(at: ifp, using: self.pathsToNodes.acquireIntoHandle())
		}

		private func destinationOfFinderAlias(at ifp: some Dirs.IntoFilePath, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath {
			let fp = try Self.resolveAncestorSymlinks(of: ifp, in: acquisitionLock.resource)

			switch acquisitionLock.resource[fp] {
				case .finderAlias(var destination, _):
					// Follow the chain like real macOS bookmark resolution does
					// If destination is another alias, follow it
					// If destination is a symlink, follow it
					do {
						return try detectCircularResolvables { recordPathVisited in
							while true {
								switch acquisitionLock.resource[destination] {
									case .finderAlias(let nextDest, _), .symlink(let nextDest, _):
										try recordPathVisited(destination)
										destination = nextDest
									default:
										// Final destination is not an alias or symlink
										return destination
								}
							}
						}
					} catch is CircularResolvableChain {
						// Real filesystem bookmark resolution returns "file doesn't exist" for circular
						// symlink chains when resolving aliases. Transform our more accurate error to
						// match the real filesystem's behavior.
						throw NoSuchNode(path: fp)
					}
				case .none: throw NoSuchNode(path: fp)
				case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
			}
		}
	#endif

	/// Creates a special node (FIFO, socket, device, etc.) for testing purposes.
	/// This is only available on MockFSInterface since this library doesn't support
	/// creating special nodes, but we want to support mocking them for testing.
	public func createSpecialForTesting(at ifp: some IntoFilePath) throws -> Special {
		try self.createNode(at: ifp, factory: Special.init, insertNode: { ptn, resolvedFP in
			ptn[resolvedFP] = .special()
		})
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		try self.replaceContentsOfFile(at: ifp, to: contents, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws {
		let fp = ifp.into()
		let contentsData = contents.into()
		let resolvedFP = try Self.resolveAncestorSymlinks(of: fp, in: acquisitionLock.resource)

		switch acquisitionLock.resource[resolvedFP] {
			case .none: throw NoSuchNode(path: fp)
			case .file(_, let xattrs): acquisitionLock.resource[resolvedFP] = .file(data: contentsData, xattrs: xattrs)
			case .symlink(let destination, _):
				let resolvedDestination = Symlink.resolveDestination(destination, relativeTo: resolvedFP)
				try self.replaceContentsOfFile(at: resolvedDestination, to: contentsData, using: acquisitionLock)
			case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
		}
	}

	public func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws {
		let acquisitionLock = self.pathsToNodes.acquireIntoHandle()
		_ = try self.copyNode(from: source, to: destination, using: acquisitionLock)
	}

	// This function extensively uses `default:` in `switch` statements to avoid
	// needing lots of `#if canImport(Darwin)` blocks for the `finderAlias` case.
	// Rest assured, Finder Aliases are just regular files (with special contents + metadata)
	private func copyNode(from source: some IntoFilePath,
						  to destination: some IntoFilePath,
						  using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath
	{
		let srcFP = try Self.resolveAncestorSymlinks(of: source, in: acquisitionLock.resource)
		let destFP = try Self.resolveAncestorSymlinks(of: destination, in: acquisitionLock.resource)

		// This is usually just `destFP`, but if `destFP` is a dir, then we
		// rehome into it, and this will be `destFP`+`srcFP.final`
		var finalDestFP = destFP

		let srcType = Self.nodeType(at: srcFP, in: acquisitionLock.resource, symRes: .dontResolve)
		let destType = Self.nodeType(at: destFP, in: acquisitionLock.resource, symRes: .dontResolve)

		func resolveDestFPSymlink() throws -> (fp: FilePath, type: NodeType?) {
			let destSymlinkDestFP = try self.destinationOf(symlink: destFP, using: acquisitionLock)
			let destType = Self.nodeType(at: destSymlinkDestFP, in: acquisitionLock.resource, symRes: .dontResolve)
			return (destSymlinkDestFP, destType)
		}

		switch srcType {
			case .none:
				throw NoSuchNode(path: srcFP)

			case .dir:
				let nodePathsToMove = acquisitionLock.resource.keys
					.filter { $0.starts(with: srcFP) }

				func recursivelyMove(destFP: FilePath) {
					for var nodePath in nodePathsToMove {
						let nodeToMove = acquisitionLock.resource[nodePath]

						let removed = nodePath.removePrefix(srcFP)
						assert(removed)
						let resolvedDestFP = destFP.appending(nodePath.components)
						acquisitionLock.resource[resolvedDestFP] = nodeToMove
					}
				}

				switch destType {
					case .symlink:
						let (destSymFP, destSymType) = try resolveDestFPSymlink()
						if destSymType == .dir {
							let resolvedDestFPRoot = destSymFP.appending(srcFP.lastComponent!)
							finalDestFP = resolvedDestFPRoot
							recursivelyMove(destFP: resolvedDestFPRoot)
						} else {
							fallthrough
						}

					#if FINDER_ALIASES_ENABLED
						case .finderAlias: fallthrough
					#endif

					case .file, .special:
						acquisitionLock.resource.removeValue(forKey: destFP)
						recursivelyMove(destFP: destFP)

					case .dir:
						let resolvedDestFPRoot = destFP.appending(srcFP.lastComponent!)
						finalDestFP = resolvedDestFPRoot
						recursivelyMove(destFP: resolvedDestFPRoot)

					case .none:
						recursivelyMove(destFP: destFP)
				}

			default:
				let fileToCopy = acquisitionLock.resource[srcFP]

				switch destType {
					case .symlink:
						let (destSymFP, destSymType) = try resolveDestFPSymlink()
						switch destSymType {
							case .dir:
								return try self.copyNode(from: source, to: destSymFP, using: acquisitionLock)

							default:
								acquisitionLock.resource[destFP] = fileToCopy
						}

					case .dir:
						let resolvedDestFP = destFP.appending(srcFP.lastComponent!)
						finalDestFP = resolvedDestFP
						acquisitionLock.resource[resolvedDestFP] = fileToCopy

					default:
						acquisitionLock.resource[destFP] = fileToCopy
				}
		}

		return finalDestFP
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		let acquisitionLock = self.pathsToNodes.acquireIntoHandle()
		try self.deleteNode(at: ifp, using: acquisitionLock)
	}

	private func deleteNode(at ifp: some IntoFilePath,
							using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws
	{
		let fp = ifp.into()
		let resolvedFP = try Self.resolveAncestorSymlinks(of: fp, in: acquisitionLock.resource)

		let keysToDelete = acquisitionLock.resource.keys
			.filter { $0.starts(with: resolvedFP) }

		guard !keysToDelete.isEmpty else {
			throw NoSuchNode(path: fp)
		}

		for key in keysToDelete {
			acquisitionLock.resource[key] = nil
		}
	}

	@discardableResult
	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws -> FilePath {
		let acquisitionLock = self.pathsToNodes.acquireIntoHandle()
		let before = acquisitionLock.resource

		do {
			let finalDestFP = try self.copyNode(from: source, to: destination, using: acquisitionLock)
			try self.deleteNode(at: source, using: acquisitionLock)
			return finalDestFP
		} catch {
			acquisitionLock.resource = before
			throw error
		}
	}

	#if XATTRS_ENABLED
		public func extendedAttributeNames(at ifp: some IntoFilePath) throws -> Set<String> {
			try self.pathsToNodes.read { ptn in
				let (node, _) = try Self.existingAncestorResolvedNode(at: ifp, in: ptn)
				return Set(node.xattrs.keys)
			}
		}

		public func extendedAttribute(named name: String, at ifp: some IntoFilePath) throws -> Data? {
			let fp = ifp.into()

			#if os(Linux)
				// Linux requires extended attribute names to be properly namespaced
				let validPrefixes = ["security.", "system.", "trusted.", "user."]
				if !validPrefixes.contains(where: { name.hasPrefix($0) }) {
					throw POSIXError(.EOPNOTSUPP, userInfo: [NSFilePathErrorKey: fp.string])
				}
			#endif

			return try self.pathsToNodes.read { ptn in
				let (node, _) = try Self.existingAncestorResolvedNode(at: ifp, in: ptn)
				return node.xattrs[name]
			}
		}

		public func setExtendedAttribute(named name: String, to value: Data, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()

			if name.utf8.count > self.maxExtendedAttributeNameLength {
				throw XAttrNameTooLong(attributeName: name, path: fp)
			}

			try self.pathsToNodes.mutate { ptn in
				var (node, resolvedFP) = try Self.existingAncestorResolvedNode(at: fp, in: ptn)

				#if os(Linux)
					// Linux kernel VFS prohibits user-namespaced xattrs on symlinks
					if node.nodeType == .symlink, name.hasPrefix("user.") {
						throw POSIXError(.EOPNOTSUPP, userInfo: [NSFilePathErrorKey: fp.string])
					}

					// Linux requires extended attribute names to be properly namespaced
					let validPrefixes = ["security.", "system.", "trusted.", "user."]
					if !validPrefixes.contains(where: { name.hasPrefix($0) }) {
						throw POSIXError(.EOPNOTSUPP, userInfo: [NSFilePathErrorKey: fp.string])
					}
				#endif

				node.xattrs[name] = value
				ptn[resolvedFP] = node
			}
		}

		public func removeExtendedAttribute(named name: String, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()
			try self.pathsToNodes.mutate { ptn in
				var (node, resolvedFP) = try Self.existingAncestorResolvedNode(at: fp, in: ptn)
				node.xattrs.removeValue(forKey: name)
				ptn[resolvedFP] = node
			}
		}
	#endif
}

@available(*, deprecated, renamed: "MockFSInterface")
public typealias MockFilesystemInterface = MockFSInterface
