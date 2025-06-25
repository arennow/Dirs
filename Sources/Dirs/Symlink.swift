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
		let destFP = destination.into()
		try self.fs.moveNode(from: self, to: destFP)
		self.path = destFP
	}
}
