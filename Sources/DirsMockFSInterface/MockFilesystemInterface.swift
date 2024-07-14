import Dirs
import Foundation
import SystemPackage

public final class MockFilesystemInterface: FilesystemInterface {
	public enum MockNode: Equatable {
		case dir
		case file(Data)
		public static func file(_ string: String) -> Self { .file(Data(string.utf8)) }
		public static var file: Self { .file(Data()) }

		var nodeType: NodeType {
			switch self {
				case .dir: .dir
				case .file: .file
			}
		}
	}

	public static func == (lhs: MockFilesystemInterface, rhs: MockFilesystemInterface) -> Bool {
		lhs.id == rhs.id
	}

	public static func empty() -> Self { Self() }

	// To allow us to avoid traversing our fake FS for deep equality
	private let id = UUID()
	private let pathsToNodes: Locked<Dictionary<FilePath, MockNode>>

	public init(pathsToNodes: Dictionary<FilePath, MockNode> = [:]) {
		var pathsToNodes = pathsToNodes
		pathsToNodes["/"] = .dir
		self.pathsToNodes = Locked(pathsToNodes)
	}

	private static func nodeType(at ifp: some IntoFilePath, in ptn: Dictionary<FilePath, MockNode>) -> NodeType? {
		ptn[ifp.into()]?.nodeType
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		self.pathsToNodes.read { ptn in
			Self.nodeType(at: ifp, in: ptn)
		}
	}

	public func contentsOf(file ifp: some IntoFilePath) throws -> Data {
		let fp = ifp.into()

		switch self.pathsToNodes[fp] {
			case .file(let data): return data
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .none: throw NoSuchNode(path: fp)
		}
	}

	public func contentsOf(directory ifp: some Dirs.IntoFilePath) throws -> Array<Dirs.FilePathStat> {
		let fp = ifp.into()

		let childKeys = self.pathsToNodes.read(in: \.keys)
			.lazy
			.filter { $0.starts(with: fp) }
			.filter { $0 != fp } // This may only remove `/`
			.filter { $0.removingLastComponent() == fp }

		return childKeys.map { childFilePath in
			switch self.pathsToNodes[childFilePath]! {
				case .dir: .init(filePath: childFilePath, isDirectory: true)
				case .file: .init(filePath: childFilePath, isDirectory: false)
			}
		}
	}

	public func filePathOfNonexistantTemporaryFile(extension: String?) -> FilePath {
		var filename = UUID().uuidString
		if let `extension` {
			filename += ".\(`extension`.trimmingCharacters(in: ["."]))"
		}

		return "/\(filename)".into()
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
			case .dir: throw NodeAlreadyExists(path: fp, type: .dir)
			case .file: throw NodeAlreadyExists(path: fp, type: .file)
			case .none:
				self.pathsToNodes[fp] = .file
				return try File(fs: self, path: fp)
		}
	}

	public func replaceContentsOfFile(at ifp: some IntoFilePath, to contents: some IntoData) throws {
		let fp = ifp.into()
		switch self.pathsToNodes[fp] {
			case .none: throw NoSuchNode(path: fp)
			case .dir: throw WrongNodeType(path: fp, actualType: .dir)
			case .file:
				self.pathsToNodes[fp] = .file(contents.into())
		}
	}

	public func deleteNode(at ifp: some IntoFilePath) throws {
		let fp = ifp.into()
		let keysToDelete = self.pathsToNodes.read(in: \.keys)
			.filter { $0.starts(with: fp) }

		for key in keysToDelete {
			self.pathsToNodes[key] = nil
		}
	}

	public func moveNode(from source: some IntoFilePath, to destination: some IntoFilePath, replacingExisting: Bool) throws {
		let srcFP: FilePath = source.into()
		let destFP: FilePath = destination.into()

		let acquisitionLock = self.pathsToNodes.acquireIntoHandle()

		let srcType = Self.nodeType(at: srcFP, in: acquisitionLock.resource)
		let destType = Self.nodeType(at: destFP, in: acquisitionLock.resource)

		switch srcType {
			case .none:
				throw NoSuchNode(path: srcFP)

			case .file:
				if !replacingExisting, destType == .file {
					throw NodeAlreadyExists(path: destFP, type: .file)
				}

				let fileToMove = acquisitionLock.resource.removeValue(forKey: srcFP)

				switch destType {
					case .file, .none:
						acquisitionLock.resource[destFP] = fileToMove

					case .dir:
						let resolvedDestFP = destFP.appending(srcFP.lastComponent!)
						acquisitionLock.resource[resolvedDestFP] = fileToMove
				}

			case .dir:
				let nodePathsToMove = acquisitionLock.resource.keys
					.filter { $0.starts(with: srcFP) }

				switch destType {
					case .file:
						throw WrongNodeType(path: destFP, actualType: .file)

					case .dir:
						let resolvedDestFPRoot = destFP.appending(srcFP.lastComponent!)
						for var nodePath in nodePathsToMove {
							let nodeToMove = acquisitionLock.resource.removeValue(forKey: nodePath)

							let removed = nodePath.removePrefix(srcFP)
							assert(removed)
							let resolvedDestFP = resolvedDestFPRoot.appending(nodePath.components)
							acquisitionLock.resource[resolvedDestFP] = nodeToMove
						}

					case .none:
						for var nodePath in nodePathsToMove {
							let nodeToMove = acquisitionLock.resource.removeValue(forKey: nodePath)

							let removed = nodePath.removePrefix(srcFP)
							assert(removed)
							let resolvedDestFP = destFP.appending(nodePath.components)
							acquisitionLock.resource[resolvedDestFP] = nodeToMove
						}
				}
		}
	}
}
