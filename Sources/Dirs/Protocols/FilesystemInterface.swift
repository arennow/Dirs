import Foundation
import SystemPackage

public struct FilePathStat: Hashable, Equatable {
	public let filePath: FilePath
	public let nodeType: NodeType

	public init(filePath: FilePath, nodeType: NodeType) {
		self.filePath = filePath
		self.nodeType = nodeType
	}
}

public enum DirLookupKind: String, Sendable {
	case home, downloads, documents, cache
	case temporary, uniqueTemporary
}

public enum NodeDateType: String, Sendable, CaseIterable {
	case creation, modification
}

public protocol FilesystemInterface: Equatable, Sendable {
	/// Returns the type of node at the given path, resolving symlinks in ancestor directories
	/// but not the final component. This allows finding nodes inside symlinked directories
	/// while still identifying symlinks themselves (rather than what they point to).
	func nodeType(at ifp: some IntoFilePath) -> NodeType?

	func contentsOf(file ifp: some IntoFilePath) throws -> Data
	func sizeOfFile(at ifp: some IntoFilePath) throws -> UInt64
	func contentsOf(directory ifp: some IntoFilePath) throws -> Array<FilePathStat>
	func destinationOf(symlink ifp: some IntoFilePath) throws -> FilePath
	func realpathOf(node ifp: some IntoFilePath) throws -> FilePath

	func lookUpDir(_ dlk: DirLookupKind) throws -> Dir

	@discardableResult
	func createFile(at ifp: some IntoFilePath) throws -> File
	@discardableResult
	func createDir(at ifp: some IntoFilePath) throws -> Dir
	@discardableResult
	func createSymlink(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> Symlink

	func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws
	func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws

	func copyNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws
	func deleteNode(at ifp: some IntoFilePath) throws
	@discardableResult
	func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath) throws -> FilePath

	func date(of type: NodeDateType, at ifp: some IntoFilePath) throws -> Date?

	// Finder Aliases are a macOS/Darwin-only system feature;
	// expose these APIs only when Darwin/Foundation is available
	#if FINDER_ALIASES_ENABLED
		@discardableResult
		func createFinderAlias(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> FinderAlias
		// By observation, the macOS implementation of this ⬇️ resolves the alias fully,
		// following chain of aliases and symlinks to the final target.
		// So that's how `MockFSInterface` implements it as well.
		func destinationOfFinderAlias(at ifp: some IntoFilePath) throws -> FilePath
	#endif

	#if XATTRS_ENABLED
		func extendedAttributeNames(at ifp: some IntoFilePath) throws -> Set<String>
		func extendedAttribute(named name: String, at ifp: some IntoFilePath) throws -> Data?
		func setExtendedAttribute(named name: String, to value: Data, at ifp: some IntoFilePath) throws
		func removeExtendedAttribute(named name: String, at ifp: some IntoFilePath) throws
	#endif
}

public extension FilesystemInterface {
	func resolvedPathAndNodeType(of ifp: some IntoFilePath) throws -> (resolvedPath: FilePath, nodeType: NodeType) {
		let resolvedPath = try self.realpathOf(node: ifp)
		guard let nodeType = self.nodeType(at: resolvedPath) else {
			throw NoSuchNode(path: resolvedPath)
		}

		return (resolvedPath, nodeType)
	}

	func nodeTypeResolvingSymlinks(at ifp: some IntoFilePath) throws -> NodeType {
		try self.resolvedPathAndNodeType(of: ifp).nodeType
	}

	/// Returns the type of node after following all resolvable nodes (symlinks and Finder aliases)
	/// to their final destination. This follows chains of resolvable nodes, such as a symlink pointing
	/// to a Finder alias pointing to another symlink, until reaching a non-resolvable node.
	///
	/// On non-Darwin platforms, this behaves identically to `nodeTypeFollowingSymlinks` since
	/// Finder aliases are Darwin-specific.
	///
	/// - Parameter ifp: The path to examine
	/// - Returns: The type of the final non-resolvable node, or `nil` if the path doesn't exist
	///   or forms a circular reference chain
	func nodeTypeResolvingResolvables(at ifp: some IntoFilePath) -> NodeType? {
		try? detectCircularResolvables { recordPathVisited in
			var currentPath = ifp.into()

			while true {
				try recordPathVisited(currentPath)

				guard let type = self.nodeType(at: currentPath) else {
					return nil
				}

				switch type {
					case .symlink:
						let destPath = try self.destinationOf(symlink: currentPath)
						currentPath = Symlink.resolveDestination(destPath, relativeTo: currentPath)

					#if FINDER_ALIASES_ENABLED
						case .finderAlias:
							let destPath = try self.destinationOfFinderAlias(at: currentPath)
							// destinationOfFinderAlias already fully resolves chains, so just return the type
							return self.nodeType(at: destPath)
					#endif

					default:
						return type
				}
			}
		}
	}
}

public extension FilesystemInterface {
	@discardableResult
	func renameNode(at source: some IntoFilePath, to newName: String) throws -> FilePath {
		if newName.contains("/") {
			throw InvalidPathForCall.needSingleComponent
		}

		let sourceFP = source.into()
		let destPath = sourceFP.removingLastComponent().appending(newName)
		if let existingNT = self.nodeType(at: destPath) {
			throw NodeAlreadyExists(path: destPath, type: existingNT)
		}
		return try self.moveNode(from: sourceFP, to: destPath)
	}
}

public extension FilesystemInterface {
	func dir(at ifp: some IntoFilePath) throws -> Dir {
		try Dir(_fs: self.asInterface, path: ifp.into())
	}

	func file(at ifp: some IntoFilePath) throws -> File {
		try File(_fs: self.asInterface, path: ifp.into())
	}

	func symlink(at ifp: some IntoFilePath) throws -> Symlink {
		try Symlink(_fs: self.asInterface, path: ifp.into())
	}

	#if SPECIALS_ENABLED
		func special(at ifp: some IntoFilePath) throws -> Special {
			try Special(_fs: self.asInterface, path: ifp.into())
		}
	#endif

	#if FINDER_ALIASES_ENABLED
		func finderAlias(at ifp: some IntoFilePath) throws -> FinderAlias {
			try FinderAlias(_fs: self.asInterface, path: ifp.into())
		}
	#endif

	func node(at ifp: some IntoFilePath) throws -> any Node {
		let fp = ifp.into()
		return switch self.nodeType(at: fp) {
			case .dir: try self.dir(at: fp)
			case .file: try self.file(at: fp)
			case .symlink: try self.symlink(at: fp)
			#if SPECIALS_ENABLED
				case .special: try self.special(at: fp)
			#endif
			#if FINDER_ALIASES_ENABLED
				case .finderAlias: try self.finderAlias(at: fp)
			#endif
			case .none: throw NoSuchNode(path: fp)
		}
	}
}

public extension FilesystemInterface {
	func appendContentsOfFile(at ifp: some IntoFilePath, with addendum: some IntoData) throws {
		let fp = ifp.into()
		var content = (try? self.contentsOf(file: fp)) ?? Data()
		content.append(addendum.into())
		try self.replaceContentsOfFile(at: fp, to: content)
	}
}

extension FilePath {
	var pathAndLeaf: (FilePath, FilePath.Component)? {
		guard self.components.count > 0 else { return nil }
		return (self.removingLastComponent(), self.lastComponent!)
	}
}

public extension FilesystemInterface {
	func isEqual(to other: any FilesystemInterface) -> Bool {
		guard let other = other as? Self else { return false }
		return self == other
	}

	var rootDir: Dir {
		get throws {
			try self.dir(at: "/")
		}
	}
}

extension FilesystemInterface {
	var asInterface: FSInterface {
		if let real = self as? RealFSInterface {
			return .real(real)
		} else if let mock = self as? MockFSInterface {
			return .mock(mock)
		} else {
			fatalError("Unknown FilesystemInterface conformer: \(type(of: self))")
		}
	}
}
