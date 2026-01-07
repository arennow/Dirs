//
//  Symlink.swift
//  Dirs
//
//  Created by Aaron Rennow on 2025-06-24.
//

@preconcurrency import SystemPackage

public struct Symlink: Node {
	public let fs: any FilesystemInterface
	public private(set) var path: FilePath

	package init(fs: any FilesystemInterface, path: some IntoFilePath) throws {
		let fp = path.into()

		switch fs.nodeType(at: fp) {
			case .none: throw NoSuchNode(path: fp)
			case .symlink: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x)
		}

		self.fs = fs
		self.path = fp
	}

	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.path)
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		self.path = try self.fs.moveNode(from: self, to: destination)
	}

	public mutating func rename(to newName: String) throws {
		self.path = try self.fs.renameNode(at: self, to: newName)
	}

	public func resolve() throws -> any Node {
		let destPath = try self.fs.destinationOf(symlink: self.path)
		return switch self.fs.nodeType(at: destPath) {
			case .dir: try Dir(fs: self.fs, path: self.path)
			case .file: try File(fs: self.fs, path: self.path)
			case .symlink: try Symlink(fs: self.fs, path: self.path)
			#if canImport(Darwin)
				case .finderAlias: try FinderAlias(fs: self.fs, path: destPath)
			#endif
			case .none: throw NoSuchNode(path: try self.fs.destinationOf(symlink: self.path))
		}
	}
}

public extension Symlink {
	func isAncestor(of other: some Node) throws -> Bool {
		try self.impl_isAncestor(of: other)
	}
}
