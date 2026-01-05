import Dirs
import Foundation
import Locked
import SystemPackage

public final class MockFSInterface: FilesystemInterface {
	private enum MockNode: Equatable {
		case dir(xattrs: Dictionary<String, Data> = [:])
		case file(data: Data = Data(), xattrs: Dictionary<String, Data> = [:])
		case symlink(destination: FilePath, xattrs: Dictionary<String, Data> = [:])
		#if canImport(Darwin)
			case finderAlias(destination: FilePath, xattrs: Dictionary<String, Data> = [:])
		#endif

		var nodeType: NodeType {
			switch self {
				case .dir: .dir
				#if canImport(Darwin)
					case .finderAlias: fallthrough
				#endif
				case .file: .file
				case .symlink: .symlink
			}
		}

		var xattrs: Dictionary<String, Data> {
			get {
				switch self {
					case .dir(let xattrs),
						 .file(_, let xattrs),
						 .symlink(_, let xattrs):
						return xattrs
					#if canImport(Darwin)
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
					#if canImport(Darwin)
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

	private static func existingParentResolvedNode(at ifp: some IntoFilePath, in ptn: PTN) throws -> (node: MockNode, resolvedPath: FilePath) {
		let fp = ifp.into()
		let resolvedFP = try Self.resolveParentSymlinks(of: fp, in: ptn)
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
	/// - Warning: This function does not yet handle `.`, `..`, `~`, etc.
	private static func realpath(of ifp: some IntoFilePath, in ptn: PTN, exceptFinalComponent: Bool = false) throws -> FilePath {
		let fp = ifp.into()

		var builtRealpathFPCV = FilePath.ComponentView()
		var builtRealpathFP: FilePath {
			FilePath(root: fp.root, builtRealpathFPCV)
		}
		let components = Array(fp.components)
		for (index, comp) in components.enumerated() {
			builtRealpathFPCV.append(comp)

			let isLastComponent = index == components.count - 1
			if exceptFinalComponent, isLastComponent {
				break
			}

			switch ptn[builtRealpathFP] {
				case .symlink(let destination, _):
					builtRealpathFPCV = .init(destination.components)
				case nil: throw NoSuchNode(path: fp)
				default: break
			}
		}

		let outThis = builtRealpathFP
		if outThis != fp {
			return try Self.realpath(of: outThis, in: ptn, exceptFinalComponent: exceptFinalComponent)
		} else {
			return outThis
		}
	}

	/// Resolves symlinks in the parent directory path and returns the path with the resolved
	/// parent and the original final component. This is used for operations that need to be
	/// able to work on nodes inside symlinked directories.
	private static func resolveParentSymlinks(of ifp: some IntoFilePath, in ptn: PTN) throws -> FilePath {
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
			#if canImport(Darwin)
				case .finderAlias:
					assertionFailure("Attempted to read contents of Finder Alias — unsupported")
					return Data()
			#endif
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .symlink(let destination, _): return try self.contentsOf(file: destination)
			case .none: throw NoSuchNode(path: fp)
		}
	}

	public func contentsOf(directory ifp: some Dirs.IntoFilePath) throws -> Array<Dirs.FilePathStat> {
		try self.contentsOf(directory: ifp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func contentsOf(directory ifp: some Dirs.IntoFilePath,
							using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> Array<Dirs.FilePathStat>
	{
		let fp = try Self.resolveParentSymlinks(of: ifp, in: acquisitionLock.resource)

		switch acquisitionLock.resource[fp] {
			case .none: throw NoSuchNode(path: fp)
			#if canImport(Darwin)
				case .finderAlias: fallthrough
			#endif
			case .file:
				throw WrongNodeType(path: fp, actualType: .file)
			case .symlink(let destination, _): return try self.contentsOf(directory: destination, using: acquisitionLock)
			case .dir: break
		}

		let childKeys = acquisitionLock.resource.keys
			.lazy
			.filter { $0.starts(with: fp) }
			.filter { $0 != fp } // This may only remove `/`
			.filter { $0.removingLastComponent() == fp }

		return childKeys.map { childFilePath in
			switch acquisitionLock.resource[childFilePath]! {
				case .dir: .init(filePath: childFilePath, isDirectory: true)
				#if canImport(Darwin)
					case .finderAlias: fallthrough
				#endif
				case .file: .init(filePath: childFilePath, isDirectory: false)
				case .symlink(let destination, _): .init(filePath: childFilePath, isDirectory: acquisitionLock.resource[destination]?.nodeType == .dir)
			}
		}
	}

	public func destinationOf(symlink ifp: some Dirs.IntoFilePath) throws -> FilePath {
		try self.destinationOf(symlink: ifp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func destinationOf(symlink ifp: some Dirs.IntoFilePath, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath {
		let fp = try Self.resolveParentSymlinks(of: ifp, in: acquisitionLock.resource)

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
			default: "/_system_\(dlk.rawValue)"
		}
		return try Dir(fs: self, path: path, createIfNeeded: true)
	}

	@discardableResult
	public func createDir(at ifp: some IntoFilePath) throws -> Dir {
		let fp = ifp.into()
		let comps = fp.components
		let eachIndex = sequence(first: comps.startIndex) { ind in
			comps.index(ind, offsetBy: 1, limitedBy: comps.endIndex)
		}
		let cumulativeFilePaths = eachIndex
			.dropFirst() // Skip root directory (always exists)
			.map { endIndex in FilePath(root: "/", fp.components[comps.startIndex..<endIndex]) }

		try self.pathsToNodes.mutate { ptn in
			for cumulativeFP in cumulativeFilePaths {
				guard cumulativeFP.lastComponent != nil else {
					preconditionFailure("Path has no last component after dropFirst()")
				}

				let resolvedDirFP = try Self.resolveParentSymlinks(of: cumulativeFP, in: ptn)

				switch ptn[resolvedDirFP] {
					#if canImport(Darwin)
						case .finderAlias: fallthrough
					#endif
					case .file:
						throw NodeAlreadyExists(path: cumulativeFP, type: .file)
					case .dir, .symlink:
						break // Already exists
					case .none:
						ptn[resolvedDirFP] = .dir()
				}
			}
		}

		return try Dir(fs: self, path: fp)
	}

	@discardableResult
	public func createFile(at ifp: some IntoFilePath) throws -> File {
		let fp = ifp.into()
		let parentFP = fp.removingLastComponent()

		try self.pathsToNodes.mutate { ptn in
			guard Self.nodeType(at: parentFP, in: ptn, symRes: .resolve) == .dir else {
				throw NoSuchNode(path: parentFP)
			}

			let resolvedFP = try Self.resolveParentSymlinks(of: fp, in: ptn)

			switch ptn[resolvedFP] {
				case .none:
					ptn[resolvedFP] = .file()
				case .some(let x): throw NodeAlreadyExists(path: fp, type: x.nodeType)
			}
		}
		return try File(fs: self, path: fp)
	}

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		let linkFP = linkIFP.into()
		try self.pathsToNodes.mutate { ptn in
			let parentFP = linkFP.removingLastComponent()
			guard Self.nodeType(at: parentFP, in: ptn, symRes: .resolve) == .dir else {
				throw NoSuchNode(path: parentFP)
			}

			let resolvedFP = try Self.resolveParentSymlinks(of: linkFP, in: ptn)

			ptn[resolvedFP] = .symlink(destination: destIFP.into())
		}
		return try Symlink(fs: self, path: linkFP)
	}

	#if canImport(Darwin)
		public func createFinderAlias(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> File {
			let linkFP = linkIFP.into()
			try self.pathsToNodes.mutate { ptn in
				let parentFP = linkFP.removingLastComponent()
				guard Self.nodeType(at: parentFP, in: ptn, symRes: .resolve) == .dir else {
					throw NoSuchNode(path: parentFP)
				}

				let resolvedFP = try Self.resolveParentSymlinks(of: linkFP, in: ptn)

				ptn[resolvedFP] = .finderAlias(destination: destIFP.into())
			}
			return try File(fs: self, path: linkFP)
		}

		public func destinationOfFinderAlias(at ifp: some Dirs.IntoFilePath) throws -> FilePath {
			try self.destinationOfFinderAlias(at: ifp, using: self.pathsToNodes.acquireIntoHandle())
		}

		private func destinationOfFinderAlias(at ifp: some Dirs.IntoFilePath, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath {
			let fp = try Self.resolveParentSymlinks(of: ifp, in: acquisitionLock.resource)

			switch acquisitionLock.resource[fp] {
				case .finderAlias(let destination, _): return destination
				case .none: throw NoSuchNode(path: fp)
				case .some(let x): throw WrongNodeType(path: fp, actualType: x.nodeType)
			}
		}
	#endif

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		try self.replaceContentsOfFile(at: ifp, to: contents, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws {
		let fp = ifp.into()
		let contentsData = contents.into()
		let resolvedFP = try Self.resolveParentSymlinks(of: fp, in: acquisitionLock.resource)

		switch acquisitionLock.resource[resolvedFP] {
			case .none: throw NoSuchNode(path: fp)
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .file(_, let xattrs): acquisitionLock.resource[resolvedFP] = .file(data: contentsData, xattrs: xattrs)
			#if canImport(Darwin)
				case .finderAlias: assertionFailure("Attempted to write contents of Finder Alias — unsupported")
			#endif
			case .symlink(let destination, _): try self.replaceContentsOfFile(at: destination, to: contentsData, using: acquisitionLock)
		}
	}

	public func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws {
		let acquisitionLock = self.pathsToNodes.acquireIntoHandle()
		_ = try self.copyNode(from: source, to: destination, using: acquisitionLock)
	}

	private func copyNode(from source: some IntoFilePath,
						  to destination: some IntoFilePath,
						  using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath
	{
		let srcFP = try Self.resolveParentSymlinks(of: source, in: acquisitionLock.resource)
		let destFP = try Self.resolveParentSymlinks(of: destination, in: acquisitionLock.resource)

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

			case .file, .symlink:
				let fileToCopy = acquisitionLock.resource[srcFP]

				switch destType {
					case .symlink:
						let (destSymFP, destSymType) = try resolveDestFPSymlink()
						switch destSymType {
							case .dir:
								return try self.copyNode(from: source, to: destSymFP, using: acquisitionLock)

							case .file, .symlink, nil:
								acquisitionLock.resource[destFP] = fileToCopy
						}

					case .file, .none:
						acquisitionLock.resource[destFP] = fileToCopy

					case .dir:
						let resolvedDestFP = destFP.appending(srcFP.lastComponent!)
						finalDestFP = resolvedDestFP
						acquisitionLock.resource[resolvedDestFP] = fileToCopy
				}

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

					case .file:
						acquisitionLock.resource.removeValue(forKey: destFP)
						recursivelyMove(destFP: destFP)

					case .dir:
						let resolvedDestFPRoot = destFP.appending(srcFP.lastComponent!)
						finalDestFP = resolvedDestFPRoot
						recursivelyMove(destFP: resolvedDestFPRoot)

					case .none:
						recursivelyMove(destFP: destFP)
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
		let resolvedFP = try Self.resolveParentSymlinks(of: fp, in: acquisitionLock.resource)

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

	#if canImport(Darwin) || os(Linux)
		public func extendedAttributeNames(at ifp: some IntoFilePath) throws -> Set<String> {
			try self.pathsToNodes.read { ptn in
				let (node, _) = try Self.existingParentResolvedNode(at: ifp, in: ptn)
				return Set(node.xattrs.keys)
			}
		}

		public func extendedAttribute(named name: String, at ifp: some IntoFilePath) throws -> Data? {
			try self.pathsToNodes.read { ptn in
				let (node, _) = try Self.existingParentResolvedNode(at: ifp, in: ptn)
				return node.xattrs[name]
			}
		}

		public func setExtendedAttribute(named name: String, to value: Data, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()

			if name.utf8.count > self.maxExtendedAttributeNameLength {
				throw XAttrNameTooLong(attributeName: name, path: fp)
			}

			try self.pathsToNodes.mutate { ptn in
				var (node, resolvedFP) = try Self.existingParentResolvedNode(at: fp, in: ptn)
				node.xattrs[name] = value
				ptn[resolvedFP] = node
			}
		}

		public func removeExtendedAttribute(named name: String, at ifp: some IntoFilePath) throws {
			let fp = ifp.into()
			try self.pathsToNodes.mutate { ptn in
				var (node, resolvedFP) = try Self.existingParentResolvedNode(at: fp, in: ptn)
				node.xattrs.removeValue(forKey: name)
				ptn[resolvedFP] = node
			}
		}
	#endif
}

@available(*, deprecated, renamed: "MockFSInterface")
public typealias MockFilesystemInterface = MockFSInterface
