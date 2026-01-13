import Foundation
import SystemPackage

public struct Dir: Node {
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

	public func hash(into hasher: inout Hasher) {
		hasher.combine(self.path)
	}

	public mutating func move(to destination: some IntoFilePath) throws {
		self.path = try self.fs.moveNode(from: self, to: destination)
	}

	public mutating func rename(to newName: String) throws {
		self.path = try self.fs.renameNode(at: self, to: newName)
	}
}

public extension Dir {
	func children() throws -> Children {
		let childFilePathStats = try self.fs.contentsOf(directory: self)
		return try Children.from(self, childStats: childFilePathStats)
	}

	private func childNode<T: Node>(named component: FilePath.Component, in listKP: KeyPath<Children, Array<T>>) -> T? {
		try? self.children()[keyPath: listKP]
			.first { node in
				node.path.lastComponent == component
			}
	}

	func childFile(named component: FilePath.Component) -> File? {
		self.childNode(named: component, in: \.files)
	}

	func childFile(named name: String) -> File? {
		FilePath.Component(name).flatMap {
			self.childNode(named: $0, in: \.files)
		}
	}

	func childDir(named name: String) -> Dir? {
		FilePath.Component(name).flatMap {
			self.childNode(named: $0, in: \.directories)
		}
	}

	func childDir(named component: FilePath.Component) -> Dir? {
		self.childNode(named: component, in: \.directories)
	}

	func childSymlink(named component: FilePath.Component) -> Symlink? {
		self.childNode(named: component, in: \.symlinks)
	}

	func childSymlink(named name: String) -> Symlink? {
		FilePath.Component(name).flatMap {
			self.childNode(named: $0, in: \.symlinks)
		}
	}

	#if canImport(Darwin)
		func childFinderAlias(named component: FilePath.Component) -> FinderAlias? {
			self.childNode(named: component, in: \.finderAliases)
		}

		func childFinderAlias(named name: String) -> FinderAlias? {
			FilePath.Component(name).flatMap {
				self.childNode(named: $0, in: \.finderAliases)
			}
		}
	#endif

	func newOrExistingChildFile(named name: String) throws -> File {
		try self.childFile(named: name) ?? self.createFile(at: name)
	}

	func newOrExistingChildDir(named name: String) throws -> Dir {
		try self.childDir(named: name) ?? self.createDir(at: name)
	}

	private func descendantNode<T: Node>(at relativePath: FilePath, extractor: (Dir) -> (FilePath.Component) -> T?) -> T? {
		var currentDir = self

		for posNextComp in relativePath.positionalComponents {
			guard !posNextComp.position.hasLast else {
				return extractor(currentDir)(posNextComp.element)
			}

			let componentPath = currentDir.path.appending(posNextComp.element)
			if case .dir = self.fs.nodeTypeFollowingSymlinks(at: componentPath) {
				if let subDir = try? self.fs.dir(at: componentPath) {
					currentDir = subDir
				} else {
					break
				}
			} else {
				break
			}
		}

		return nil
	}

	func descendantFile(at relativePath: FilePath) -> File? {
		self.descendantNode(at: relativePath, extractor: Dir.childFile)
	}

	func descendantDir(at relativePath: FilePath) -> Dir? {
		self.descendantNode(at: relativePath, extractor: Dir.childDir)
	}

	func descendantSymlink(at relativePath: FilePath) -> Symlink? {
		self.descendantNode(at: relativePath, extractor: Dir.childSymlink)
	}

	#if canImport(Darwin)
		func descendantFinderAlias(at relativePath: FilePath) -> FinderAlias? {
			self.descendantNode(at: relativePath, extractor: Dir.childFinderAlias)
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
			#if canImport(Darwin)
				var finderAliases: Array<FinderAlias>
			#endif
		}

		let state = if let children = try? self.children() {
			#if canImport(Darwin)
				State(dirs: children.directories, files: children.files, symlinks: children.symlinks, finderAliases: children.finderAliases)
			#else
				State(dirs: children.directories, files: children.files, symlinks: children.symlinks)
			#endif
		} else {
			#if canImport(Darwin)
				State(dirs: [], files: [], symlinks: [], finderAliases: [])
			#else
				State(dirs: [], files: [], symlinks: [])
			#endif
		}

		return sequence(state: state) { state -> Optional<any Node> in
			if let nextFile = state.files.popLast() {
				return nextFile
			}

			if let nextSymlink = state.symlinks.popLast() {
				return nextSymlink
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
}
