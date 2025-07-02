import Dirs
import Foundation
import SystemPackage

public final class MockFilesystemInterface: FilesystemInterface {
	private enum MockNode: Equatable {
		case dir
		case file(Data)
		public static func file(_ string: String) -> Self { .file(Data(string.utf8)) }
		public static var file: Self { .file(Data()) }
		case symlink(FilePath)

		var nodeType: NodeType {
			switch self {
				case .dir: .dir
				case .file: .file
				case .symlink: .symlink
			}
		}
	}

	private enum SymlinkResolutionBehavior {
		case resolve, dontResolve

		func properFilePath(for ifp: some IntoFilePath, in ptn: PTN) -> FilePath? {
			let fp = ifp.into()

			do {
				return switch self {
					case .resolve:
						try MockFilesystemInterface.realpath(of: fp, in: ptn)
					case .dontResolve:
						fp
				}
			} catch {
				return nil
			}
		}
	}

	private typealias PTN = Dictionary<FilePath, MockNode>

	public static func == (lhs: MockFilesystemInterface, rhs: MockFilesystemInterface) -> Bool {
		lhs.id == rhs.id
	}

	public static func empty() -> Self { Self() }

	// To allow us to avoid traversing our fake FS for deep equality
	private let id = UUID()
	private let pathsToNodes: Locked<PTN>

	private init() {
		self.pathsToNodes = Locked(["/": .dir])
	}

	private static func node(at ifp: some IntoFilePath, in ptn: PTN, symRes: SymlinkResolutionBehavior) -> MockNode? {
		if let properFP = symRes.properFilePath(for: ifp, in: ptn) {
			ptn[properFP]
		} else {
			nil
		}
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
	private static func realpath(of ifp: some IntoFilePath, in ptn: PTN) throws -> FilePath {
		let fp = ifp.into()

		var builtRealpathFPCV = FilePath.ComponentView()
		var builtRealpathFP: FilePath {
			FilePath(root: fp.root, builtRealpathFPCV)
		}
		for comp in fp.components {
			builtRealpathFPCV.append(comp)

			switch ptn[builtRealpathFP] {
				case .symlink(let destination):
					builtRealpathFPCV = .init(destination.components)
				case nil: throw NoSuchNode(path: fp)
				default: break
			}
		}

		let outThis = builtRealpathFP
		if outThis != fp {
			return try Self.realpath(of: outThis, in: ptn)
		} else {
			return outThis
		}
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
			node = self.node(at: ifp, symRes: .resolve)
		}

		return node?.nodeType
	}

	public func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType? {
		self.node(at: ifp, symRes: .resolve)?.nodeType
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		let fp = ifp.into()

		switch self.node(at: fp, symRes: .resolve) {
			case .file(let data): return data
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .symlink(let destination): return try self.contentsOf(file: destination)
			case .none: throw NoSuchNode(path: fp)
		}
	}

	public func contentsOf(directory ifp: some Dirs.IntoFilePath) throws -> Array<Dirs.FilePathStat> {
		try self.contentsOf(directory: ifp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func contentsOf(directory ifp: some Dirs.IntoFilePath,
							using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> Array<Dirs.FilePathStat>
	{
		let fp = ifp.into()

		switch acquisitionLock.resource[fp] {
			case .none: throw NoSuchNode(path: fp)
			case .file: throw WrongNodeType(path: fp, actualType: .file)
			case .symlink(let destination): return try self.contentsOf(directory: destination, using: acquisitionLock)
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
				case .file: .init(filePath: childFilePath, isDirectory: false)
				case .symlink(let destination): .init(filePath: childFilePath, isDirectory: acquisitionLock.resource[destination]?.nodeType == .dir)
			}
		}
	}

	public func destinationOf(symlink ifp: some Dirs.IntoFilePath) throws -> FilePath {
		try self.destinationOf(symlink: ifp, using: self.pathsToNodes.acquireIntoHandle())
	}

	private func destinationOf(symlink ifp: some Dirs.IntoFilePath, using acquisitionLock: borrowing Locked<PTN>.AcquisitionHandle) throws -> FilePath {
		let fp = ifp.into()

		switch acquisitionLock.resource[fp] {
			case .symlink(let destination): return destination
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
			case .uniqueTemporary: "/_temporary_\(UUID().uuidString)"
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
		let allDirectories = eachIndex.map { endIndex in
			FilePath(root: "/", fp.components[comps.startIndex..<endIndex])
		}
		for dirComponent in allDirectories {
			if case .file = self.pathsToNodes[dirComponent] {
				throw NodeAlreadyExists(path: dirComponent, type: .file)
			} else {
				self.pathsToNodes[dirComponent] = .dir
			}
		}

		return try Dir(fs: self, path: fp)
	}

	@discardableResult
	public func createFile(at ifp: some IntoFilePath) throws -> File {
		let fp = ifp.into()
		let containingDirFP = fp.removingLastComponent()
		guard self.nodeType(at: containingDirFP) == .dir else {
			throw NoSuchNode(path: containingDirFP)
		}

		switch self.pathsToNodes[fp] {
			case .none:
				self.pathsToNodes[fp] = .file
				return try File(fs: self, path: fp)
			case .some(let x): throw NodeAlreadyExists(path: fp, type: x.nodeType)
		}
	}

	public func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink {
		let linkFP = linkIFP.into()
		self.pathsToNodes[linkFP] = .symlink(destIFP.into())
		return try Symlink(fs: self, path: linkFP)
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		let fp = ifp.into()
		switch self.pathsToNodes[fp] {
			case .none: throw NoSuchNode(path: fp)
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .file: self.pathsToNodes[fp] = .file(contents.into())
			case .symlink(let destination): try self.replaceContentsOfFile(at: destination, to: contents)
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
		let srcFP: FilePath = source.into()
		let destFP: FilePath = destination.into()

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

		let keysToDelete = acquisitionLock.resource.keys
			.filter { $0.starts(with: fp) }

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
}
