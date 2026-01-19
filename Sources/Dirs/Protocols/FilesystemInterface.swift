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

public enum NodeType: Sendable {
	case dir, file, symlink
	#if canImport(Darwin)
		case finderAlias
	#endif
}

public enum DirLookupKind: String, Sendable {
	case home, downloads, documents, cache
	case temporary, uniqueTemporary
}

public protocol FilesystemInterface: Equatable, Sendable {
	/// Returns the type of node at the given path, resolving symlinks in parent directories
	/// but not the final component. This allows finding nodes inside symlinked directories
	/// while still identifying symlinks themselves (rather than what they point to).
	func nodeType(at ifp: some IntoFilePath) -> NodeType?

	/// Returns the type of node after following all symlinks to their final destination.
	func nodeTypeFollowingSymlinks(at ifp: some IntoFilePath) -> NodeType?

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

	// Finder Aliases are a macOS/Darwin-only system feature;
	// expose these APIs only when Darwin/Foundation is available
	#if canImport(Darwin)
		@discardableResult
		func createFinderAlias(at linkIFP: some IntoFilePath, to destIFP: some IntoFilePath) throws -> FinderAlias
		// By observation, the macOS implementation of this ⬇️ resolves the alias fully,
		// following chain of aliases and symlinks to the final target.
		// So that's how `MockFSInterface` implements it as well.
		func destinationOfFinderAlias(at ifp: some IntoFilePath) throws -> FilePath
	#endif

	#if canImport(Darwin) || os(Linux)
		func extendedAttributeNames(at ifp: some IntoFilePath) throws -> Set<String>
		func extendedAttribute(named name: String, at ifp: some IntoFilePath) throws -> Data?
		func setExtendedAttribute(named name: String, to value: Data, at ifp: some IntoFilePath) throws
		func removeExtendedAttribute(named name: String, at ifp: some IntoFilePath) throws
	#endif
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

	#if canImport(Darwin)
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
			#if canImport(Darwin)
				case .finderAlias: try self.finderAlias(at: fp)
			#endif
			case .none: throw NoSuchNode(path: fp)
		}
	}

	@discardableResult
	func createFileAndIntermediaryDirs(at ifp: some IntoFilePath) throws -> File {
		guard let (path, leaf) = ifp.into().pathAndLeaf else {
			throw InvalidPathForCall.needAbsoluteWithComponent
		}

		let dir = try self.rootDir.createDir(at: path)
		let file = try dir.createFile(at: leaf)
		return file
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
