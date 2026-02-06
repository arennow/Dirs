import Algorithms

public struct Children {
	public private(set) var directories: Array<Dir>
	public private(set) var files: Array<File>
	public private(set) var symlinks: Array<Symlink>
	public private(set) var specials: Array<Special>
	#if FINDER_ALIASES_ENABLED
		public private(set) var finderAliases: Array<FinderAlias>

		init(directories: consuming Array<Dir>,
			 files: consuming Array<File>,
			 symlinks: consuming Array<Symlink>,
			 specials: consuming Array<Special>,
			 finderAliases: consuming Array<FinderAlias>)
		{
			self.directories = directories
			self.files = files
			self.symlinks = symlinks
			self.specials = specials
			self.finderAliases = finderAliases
		}
	#else
		init(directories: consuming Array<Dir>,
			 files: consuming Array<File>,
			 symlinks: consuming Array<Symlink>,
			 specials: consuming Array<Special>)
		{
			self.directories = directories
			self.files = files
			self.symlinks = symlinks
			self.specials = specials
		}
	#endif

	static func from(_ dir: Dir, childStats: Array<FilePathStat>) -> Self {
		var dirs = Array<Dir>()
		var files = Array<File>()
		var symlinks = Array<Symlink>()
		var specials = Array<Special>()
		#if FINDER_ALIASES_ENABLED
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
				case .special:
					specials.append(Special(uncheckedAt: childStat.filePath, in: dir._fs))
				#if FINDER_ALIASES_ENABLED
					case .finderAlias:
						finderAliases.append(FinderAlias(uncheckedAt: childStat.filePath, in: dir._fs))
				#endif
			}
		}

		#if FINDER_ALIASES_ENABLED
			return Self(directories: dirs, files: files, symlinks: symlinks, specials: specials, finderAliases: finderAliases)
		#else
			return Self(directories: dirs, files: files, symlinks: symlinks, specials: specials)
		#endif
	}

	public mutating func resolveResolvables() throws {
		func resolveArray(_ resolvables: inout Array<some ResolvableNode>) throws {
			while let resolvable = resolvables.popLast() {
				switch resolvable.fs.nodeTypeResolvingResolvables(at: resolvable.path) {
					case .none:
						continue // broken resolvables get filtered out
					case .dir:
						self.directories.append(Dir(uncheckedAt: resolvable.path, in: resolvable.fs.asInterface))
					case .file:
						self.files.append(File(uncheckedAt: resolvable.path, in: resolvable.fs.asInterface))
					case .special:
						self.specials.append(Special(uncheckedAt: resolvable.path, in: resolvable.fs.asInterface))
					default:
						fatalError("Unrecognized or unexpected node type returned from resolve(): \(resolvable.path)")
				}
			}

			assert(resolvables.isEmpty)
		}

		try resolveArray(&self.symlinks)
		#if FINDER_ALIASES_ENABLED
			try resolveArray(&self.finderAliases)
		#endif
	}
}

public extension Children {
	var all: some Sequence<any Node> {
		let base: some Sequence<any Node> = chain(chain(chain(self.directories, self.files), self.symlinks), self.specials)
		#if FINDER_ALIASES_ENABLED
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
			&& self.specials.isEmpty
		#if FINDER_ALIASES_ENABLED
			return baseEmpty && self.finderAliases.isEmpty
		#else
			return baseEmpty
		#endif
	}

	public var count: Int {
		let baseCount = self.directories.count + self.files.count + self.symlinks.count + self.specials.count
		#if FINDER_ALIASES_ENABLED
			return baseCount + self.finderAliases.count
		#else
			return baseCount
		#endif
	}
}
