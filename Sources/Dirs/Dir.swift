import Foundation
import SystemPackage

public struct Dir: Node {
	public static let nodeType: NodeType = .dir

	let _fs: FSInterface
	public var fs: any FilesystemInterface { self._fs.wrapped }
	public private(set) var path: FilePath

	init(_fs: FSInterface, path: some IntoFilePath, createIfNeeded: Bool = false) throws {
		let fp = path.into()

		switch _fs.wrapped.nodeTypeFollowingSymlinks(at: fp) {
			case .none:
				if createIfNeeded {
					self = try _fs.wrapped.createDir(at: fp)
					return
				} else {
					throw NoSuchNode(path: fp)
				}
			case .dir: break
			case .some(let x): throw WrongNodeType(path: fp, actualType: x)
		}

		self._fs = _fs
		self.path = fp
	}

	init(uncheckedAt path: FilePath, in fs: FSInterface) {
		self._fs = fs
		self.path = path
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		self.path = try self.fs.moveNode(from: self, to: self.ensureAbsolutePath(of: destination))
	}

	public mutating func rename(to newName: String) throws {
		self.path = try self.fs.renameNode(at: self, to: newName)
	}
}

public extension Dir {
	/// Returns the immediate children of this directory without resolving
	/// any symlinks or Finder aliases.
	/// - Returns: A `Children` structure containing all immediate child nodes.
	func children() throws -> Children {
		let childFilePathStats = try self.fs.contentsOf(directory: self)
		return Children.from(self, childStats: childFilePathStats)
	}

	/// Returns the immediate children of this directory with all
	/// symlinks and Finder aliases resolved.
	///
	/// This is a convenience function that calls `children()` and then
	/// calls `Children.resolveResolvables()` on the results
	/// to resolve any symlinks or Finder aliases contained within them.
	///
	/// The returned `Children` structure will never have any members in
	/// its `symlinks` or `finderAliases` arrays, as all such nodes will have been
	/// resolved to their targets (which are added to the appropriate arrays).
	/// - Returns: A `Children` structure with all resolvable nodes resolved to their final targets.
	func resolvedChildren() throws -> Children {
		var children = try self.children()
		try children.resolveResolvables()
		return children
	}

	func newOrExistingFile(at relativeIFP: some IntoFilePath) throws -> File {
		let absolutePath = self.path.appending(relativeIFP.into().components)
		if let existing = try? self.fs.file(at: absolutePath) {
			return existing
		} else {
			if let (parent, _) = absolutePath.pathAndLeaf {
				_ = try self.newOrExistingDir(at: parent)
			}
			return try self.fs.createFile(at: absolutePath)
		}
	}

	func newOrExistingDir(at relativeIFP: some IntoFilePath) throws -> Dir {
		let absolutePath = self.path.appending(relativeIFP.into().components)
		if let existing = try? self.fs.dir(at: absolutePath) {
			return existing
		} else {
			return try self.fs.createDir(at: absolutePath)
		}
	}

	private func typedNode<T>(at relativePath: some IntoFilePath, nodeGetter: (any FilesystemInterface, FilePath) throws -> T) -> T? {
		// The FS interfaces handle all intermediate path validation
		let absolutePath = self.path.appending(relativePath.into().components)
		return try? nodeGetter(self.fs, absolutePath)
	}

	func node(at relativeIFP: some IntoFilePath) -> Optional<any Node> {
		self.typedNode(at: relativeIFP, nodeGetter: { try $0.node(at: $1) })
	}

	func file(at relativeIFP: some IntoFilePath) -> File? {
		self.typedNode(at: relativeIFP, nodeGetter: { try $0.file(at: $1) })
	}

	func dir(at relativeIFP: some IntoFilePath) -> Dir? {
		self.typedNode(at: relativeIFP, nodeGetter: { try $0.dir(at: $1) })
	}

	func symlink(at relativeIFP: some IntoFilePath) -> Symlink? {
		self.typedNode(at: relativeIFP, nodeGetter: { try $0.symlink(at: $1) })
	}

	#if canImport(Darwin)
		func finderAlias(at relativeIFP: some IntoFilePath) -> FinderAlias? {
			self.typedNode(at: relativeIFP, nodeGetter: { try $0.finderAlias(at: $1) })
		}
	#endif

	func isAncestor(of other: some Node) throws -> Bool {
		try self.impl_isAncestor(of: other)
	}
}

public extension Dir {
	func allDescendantNodes() -> some Sequence<any Node> {
		struct State {
			var dirs: Array<Dir>
			var files: Array<File>
			var symlinks: Array<Symlink>
			var specials: Array<Special>
			#if canImport(Darwin)
				var finderAliases: Array<FinderAlias>
			#endif
		}

		let state = if let children = try? self.children() {
			#if canImport(Darwin)
				State(dirs: children.directories, files: children.files, symlinks: children.symlinks, specials: children.specials, finderAliases: children.finderAliases)
			#else
				State(dirs: children.directories, files: children.files, symlinks: children.symlinks, specials: children.specials)
			#endif
		} else {
			#if canImport(Darwin)
				State(dirs: [], files: [], symlinks: [], specials: [], finderAliases: [])
			#else
				State(dirs: [], files: [], symlinks: [], specials: [])
			#endif
		}

		return sequence(state: state) { state -> Optional<any Node> in
			if let nextFile = state.files.popLast() {
				return nextFile
			}

			if let nextSymlink = state.symlinks.popLast() {
				return nextSymlink
			}

			if let nextSpecial = state.specials.popLast() {
				return nextSpecial
			}

			#if canImport(Darwin)
				if let nextFinderAlias = state.finderAliases.popLast() {
					return nextFinderAlias
				}
			#endif

			if let nextDir = state.dirs.popLast() {
				if let children = try? nextDir.children() {
					state.dirs.append(contentsOf: children.directories)
					state.files.append(contentsOf: children.files)
					state.symlinks.append(contentsOf: children.symlinks)
					state.specials.append(contentsOf: children.specials)
					#if canImport(Darwin)
						state.finderAliases.append(contentsOf: children.finderAliases)
					#endif
				}
				return nextDir
			}

			return nil
		}
	}

	func allDescendantFiles() -> some Sequence<File> {
		self.allDescendantNodes().compactMap { $0 as? File }
	}

	func allDescendantDirs() -> some Sequence<Dir> {
		self.allDescendantNodes().compactMap { $0 as? Dir }
	}

	func allDescendantSymlinks() -> some Sequence<Symlink> {
		self.allDescendantNodes().compactMap { $0 as? Symlink }
	}

	func allDescendantSpecials() -> some Sequence<Special> {
		self.allDescendantNodes().compactMap { $0 as? Special }
	}

	#if canImport(Darwin)
		func allDescendantFinderAliases() -> some Sequence<FinderAlias> {
			self.allDescendantNodes().compactMap { $0 as? FinderAlias }
		}
	#endif
}

public extension Dir {
	@discardableResult
	func createDir(at ifpcv: some IntoFilePathComponentView) throws -> Dir {
		try self.fs.createDir(at: self.path.appending(ifpcv.into()))
	}

	@discardableResult
	func createFile(at ifpcv: some IntoFilePathComponentView) throws -> File {
		try self.fs.createFile(at: self.path.appending(ifpcv.into()))
	}

	@discardableResult
	func createSymlink(at ifpcv: some IntoFilePathComponentView, to destination: some IntoFilePath) throws -> Symlink {
		try self.fs.createSymlink(at: self.path.appending(ifpcv.into()), to: destination.into())
	}

	#if canImport(Darwin)
		@discardableResult
		func createFinderAlias(at ifpcv: some IntoFilePathComponentView, to destination: some IntoFilePath) throws -> FinderAlias {
			try self.fs.createFinderAlias(at: self.path.appending(ifpcv.into()), to: destination.into())
		}
	#endif
}
