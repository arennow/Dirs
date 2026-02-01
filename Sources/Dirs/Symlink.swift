//
//  Symlink.swift
//  Dirs
//
//  Created by Aaron Rennow on 2025-06-24.
//

import SystemPackage

public struct Symlink: ResolvableNode {
	public static let nodeType: NodeType = .symlink
	public static let resolvableNodeType: ResolvableNodeType = .symlink

	let _fs: FSInterface
	public var fs: any FilesystemInterface { self._fs.wrapped }
	public private(set) var path: FilePath

	init(_fs: FSInterface, path: some IntoFilePath) throws {
		let fp = path.into()

		// Intentionally check with `nodeType` (which resolves symlinks in
		// parent directories but does NOT follow the final component). We
		// want to validate that the path *itself* is a symlink and not the
		// type of its referent. Other concrete inits (e.g. `File`/`Dir`)
		// use `nodeTypeFollowingSymlinks` because they care about the
		// resolved target type; `Symlink` must specifically identify the
		// symlink node.
		switch _fs.wrapped.nodeType(at: fp) {
			case .none: throw NoSuchNode(path: fp)
			case .symlink: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x)
		}

		self._fs = _fs
		self.path = fp
	}

	init(uncheckedAt path: FilePath, in fs: FSInterface) {
		self._fs = fs
		self.path = path
	}

	/// Resolves a symlink destination path relative to the symlink's location.
	/// If the destination is relative, it is resolved relative to the symlink's parent directory.
	/// Absolute destinations are returned unchanged.
	static func resolveDestination(_ destination: FilePath, relativeTo symlinkPath: FilePath) -> FilePath {
		if destination.root == nil {
			let parent = symlinkPath.removingLastComponent()
			return parent.appending(destination.components)
		} else {
			return destination
		}
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		self.path = try self.fs.moveNode(from: self, to: self.ensureAbsolutePath(of: destination))
	}

	public mutating func rename(to newName: String) throws {
		self.path = try self.fs.renameNode(at: self, to: newName)
	}

	public var destination: FilePath {
		get throws { try self.fs.destinationOf(symlink: self.path) }
	}

	public func resolve() throws -> any Node {
		let destPath = try self.destination
		let resolvedPath = Self.resolveDestination(destPath, relativeTo: self.path)
		return try self.fs.node(at: resolvedPath)
	}
}

public extension Symlink {
	func isAncestor(of other: some Node) throws -> Bool {
		try self.impl_isAncestor(of: other)
	}
}
