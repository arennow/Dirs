import Algorithms

public struct Children {
	public let directories: Array<Dir>
	public let files: Array<File>
	public let symlinks: Array<Symlink>
	#if canImport(Darwin)
		public let finderAliases: Array<FinderAlias>

		init(directories: consuming Array<Dir>,
			 files: consuming Array<File>,
			 symlinks: consuming Array<Symlink>,
			 finderAliases: consuming Array<FinderAlias>)
		{
			self.directories = directories
			self.files = files
			self.symlinks = symlinks
			self.finderAliases = finderAliases
		}
	#else
		init(directories: consuming Array<Dir>,
			 files: consuming Array<File>,
			 symlinks: consuming Array<Symlink>)
		{
			self.directories = directories
			self.files = files
			self.symlinks = symlinks
		}
	#endif

	static func from(_ dir: Dir, childStats: Array<FilePathStat>) -> Self {
		var dirs = Array<Dir>()
		var files = Array<File>()
		var symlinks = Array<Symlink>()
		#if canImport(Darwin)
			var finderAliases = Array<FinderAlias>()
		#endif

		for childStat in childStats {
			switch childStat.nodeType {
				case .dir:
					dirs.append(Dir(uncheckedAt: childStat.filePath, in: dir._fs))
				case .file:
					files.append(File(uncheckedAt: childStat.filePath, in: dir._fs))
				case .symlink:
					symlinks.append(Symlink(uncheckedAt: childStat.filePath, in: dir._fs))
				#if canImport(Darwin)
					case .finderAlias:
						finderAliases.append(FinderAlias(uncheckedAt: childStat.filePath, in: dir._fs))
				#endif
			}
		}

		#if canImport(Darwin)
			return Self(directories: dirs, files: files, symlinks: symlinks, finderAliases: finderAliases)
		#else
			return Self(directories: dirs, files: files, symlinks: symlinks)
		#endif
	}
}

public extension Children {
	var all: some Sequence<any Node> {
		let base: some Sequence<any Node> = chain(chain(self.directories, self.files), self.symlinks)
		#if canImport(Darwin)
			return chain(base, self.finderAliases)
		#else
			return base
		#endif
	}
}

extension Children: Sequence {
	public func makeIterator() -> some IteratorProtocol<any Node> {
		self.all.makeIterator()
	}

	public var isEmpty: Bool {
		let baseEmpty = self.directories.isEmpty
			&& self.files.isEmpty
			&& self.symlinks.isEmpty
		#if canImport(Darwin)
			return baseEmpty && self.finderAliases.isEmpty
		#else
			return baseEmpty
		#endif
	}

	public var count: Int {
		let baseCount = self.directories.count + self.files.count + self.symlinks.count
		#if canImport(Darwin)
			return baseCount + self.finderAliases.count
		#else
			return baseCount
		#endif
	}
}
