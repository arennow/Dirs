import Foundation
import SystemPackage

public struct Dir: Node {
	public let fs: any FilesystemInterface
	public let path: FilePath

	public init(fs: any FilesystemInterface, path: FilePath) throws {
		switch fs.nodeType(at: path) {
			case .file: throw WrongNodeType(path: path, actualType: .file)
			case .none: throw NoSuchNode(path: path)
			case .dir: break
		}

		self.fs = fs
		self.path = path
	}
}

public extension Dir {
	func children() throws -> Children {
		var dirs = Array<Dir>()
		var files = Array<File>()

		let childFilePathStats = try self.fs.contentsOf(directory: self)

		for childFilePathStat in childFilePathStats {
			if childFilePathStat.isDirectory {
				dirs.append(try .init(fs: self.fs, path: childFilePathStat.filePath))
			} else {
				files.append(try .init(fs: self.fs, path: childFilePathStat.filePath))
			}
		}

		return Children(directories: dirs, files: files)
	}
}
