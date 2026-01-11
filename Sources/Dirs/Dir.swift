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
		var dirs = Array<Dir>()
		var files = Array<File>()

		let childFilePathStats = try self.fs.contentsOf(directory: self)

		for childFilePathStat in childFilePathStats {
			if childFilePathStat.isDirectory {
				dirs.append(try .init(_fs: self._fs, path: childFilePathStat.filePath))
			} else {
				files.append(try .init(_fs: self._fs, path: childFilePathStat.filePath))
			}
		}

		return Children(directories: dirs, files: files)
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

			if let subDir = currentDir.childDir(named: posNextComp.element) {
				currentDir = subDir
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

	func isAncestor(of other: some Node) throws -> Bool {
		try self.impl_isAncestor(of: other)
	}
}

public extension Dir {
	func allDescendantNodes() -> some Sequence<any Node> {
		struct State {
			var dirs: Array<Dir>
			var files: Array<File>
		}

		let state = if let children = try? self.children() {
			State(dirs: children.directories,
				  files: children.files)
		} else {
			State(dirs: [],
				  files: [])
		}

		return sequence(state: state) { state -> Optional<any Node> in
			if let nextFile = state.files.popLast() {
				return nextFile
			} else if let nextDir = state.dirs.popLast() {
				if let children = try? nextDir.children() {
					state.dirs.append(contentsOf: children.directories)
					state.files.append(contentsOf: children.files)
				}
				return nextDir
			} else {
				return nil
			}
		}
	}

	func allDescendantFiles() -> some Sequence<File> {
		self.allDescendantNodes().compactMap { $0 as? File }
	}

	func allDescendantDirs() -> some Sequence<Dir> {
		self.allDescendantNodes().compactMap { $0 as? Dir }
	}
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
