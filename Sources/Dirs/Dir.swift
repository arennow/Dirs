import Foundation
@preconcurrency import SystemPackage

public struct Dir: Node {
	public let fs: any FilesystemInterface
	public private(set) var path: FilePath

	public init(fs: any FilesystemInterface, path: some IntoFilePath, createIfNeeded: Bool = false) throws {
		let fp = path.into()

		switch fs.nodeTypeFollowingSymlinks(at: fp) {
			case .none:
				if createIfNeeded {
					self = try fs.createDir(at: fp)
					return
				} else {
					throw NoSuchNode(path: fp)
				}
			case .dir: break
			case .file: throw WrongNodeType(path: fp, actualType: .file)
			case .symlink:
				let destinationPath = try fs.destinationOf(symlink: fp)
				self = try Dir(fs: fs, path: destinationPath)
				return
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
