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

	static func from(_ dir: Dir, childStats: Array<FilePathStat>) throws -> Self {
		var dirs = Array<Dir>()
		var files = Array<File>()
		var symlinks = Array<Symlink>()
		#if canImport(Darwin)
			var finderAliases = Array<FinderAlias>()
		#endif

		for childStat in childStats {
			switch childStat.nodeType {
				case .dir:
					dirs.append(try dir.fs.dir(at: childStat.filePath))
				case .file:
					files.append(try dir.fs.file(at: childStat.filePath))
				case .symlink:
					symlinks.append(try dir.fs.symlink(at: childStat.filePath))
				#if canImport(Darwin)
					case .finderAlias:
						finderAliases.append(try dir.fs.finderAlias(at: childStat.filePath))
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

	var isEmpty: Bool {
		let baseEmpty = self.directories.isEmpty
			&& self.files.isEmpty
			&& self.symlinks.isEmpty
		#if canImport(Darwin)
			return baseEmpty && self.finderAliases.isEmpty
		#else
			return baseEmpty
		#endif
	}
}
