import Dirs
import Foundation
import SystemPackage

public final class MockFilesystemInterface: FilesystemInterface {
	public enum MockNode {
		case dir
		case file(Data)
		public static var file: Self { .file(Data()) }

		var nodeType: NodeType {
			switch self {
				case .dir: .dir
				case .file: .file
			}
		}
	}

	public static func empty() -> Self { Self() }

	private var pathsToNodes: Dictionary<FilePath, MockNode>

	public init(pathsToNodes: Dictionary<FilePath, MockNode> = [:]) {
		var pathsToNodes = pathsToNodes
		pathsToNodes["/"] = .dir
		self.pathsToNodes = pathsToNodes
	}

	public func nodeType(at ifp: some IntoFilePath) -> NodeType? {
		self.pathsToNodes[ifp.into()]?.nodeType
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

		let childKeys = self.pathsToNodes.keys
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

	// TODO: Don't clobber existing nodes
	public func createDir(at fp: FilePath) throws -> Dir {
		let comps = fp.components
		let eachIndex = sequence(first: comps.startIndex) { ind in
			comps.index(ind, offsetBy: 1, limitedBy: comps.endIndex)
		}
		let intermediaryDirectories = eachIndex.map { endIndex in
			FilePath(root: "/", fp.components[comps.startIndex..<endIndex])
		}
		for dirComponent in intermediaryDirectories {
			self.pathsToNodes[dirComponent] = .dir
		}

		return try Dir(fs: self, path: fp)
	}

	public func createFile(at fp: FilePath) throws -> Dirs.File {
		let containingDirFP = fp.removingLastComponent()
		guard self.nodeType(at: containingDirFP) == .dir else {
			throw NoSuchNode(path: containingDirFP)
		}

		self.pathsToNodes[fp] = .file
		return try File(fs: self, path: fp)
	}
}
