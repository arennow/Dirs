//
//  FinderAlias.swift
//  Dirs
//
//  Created by Aaron Rennow on 2025-01-05.
//

#if canImport(Darwin)
	import SystemPackage

	public struct FinderAlias: ResolvableNode {
		public static let nodeType: NodeType = .finderAlias
		public static let resolvableNodeType: ResolvableNodeType = .finderAlias

		let _fs: FSInterface
		public var fs: any FilesystemInterface { self._fs.wrapped }
		public private(set) var path: FilePath

		init(_fs: FSInterface, path: some IntoFilePath) throws {
			let fp = path.into()

			// Finder aliases are effectively regular files carrying extra
			// metadata (they are not the same kind of filesystem node as a
			// symlink). For the purpose of validating the node type at the
			// given path we want the resolved target type (the same rationale
			// used for `File`/`Dir`), so we use
			// `nodeTypeFollowingSymlinks(at:)` here rather than the symlink-
			// preserving `nodeType(at:)`.
			switch _fs.wrapped.nodeTypeFollowingSymlinks(at: fp) {
				case .none: throw NoSuchNode(path: fp)
				case .finderAlias: break
				case .some(let x): throw WrongNodeType(path: fp, actualType: x)
			}

			self._fs = _fs
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
			let destPath = try self.fs.destinationOfFinderAlias(at: self.path)
			return try self.fs.node(at: destPath)
		}
	}
#endif
