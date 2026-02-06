import Algorithms

public struct Children {
	public private(set) var directories: Array<Dir>
	public private(set) var files: Array<File>
	public private(set) var symlinks: Array<Symlink>
	#if SPECIALS_ENABLED
		public private(set) var specials: Array<Special>
	#endif
	#if FINDER_ALIASES_ENABLED
		public private(set) var finderAliases: Array<FinderAlias>
	#endif

	static func from(_ dir: Dir, childStats: Array<FilePathStat>) -> Self {
		var dirs = Array<Dir>()
		var files = Array<File>()
		var symlinks = Array<Symlink>()
		#if SPECIALS_ENABLED
			var specials = Array<Special>()
		#endif
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
				#if SPECIALS_ENABLED
					case .special:
						specials.append(Special(uncheckedAt: childStat.filePath, in: dir._fs))
				#endif
				#if FINDER_ALIASES_ENABLED
					case .finderAlias:
						finderAliases.append(FinderAlias(uncheckedAt: childStat.filePath, in: dir._fs))
				#endif
			}
		}

		#if FINDER_ALIASES_ENABLED
			return Self(directories: dirs,
						files: files,
						symlinks: symlinks,
						specials: specials,
						finderAliases: finderAliases)
		#elseif SPECIALS_ENABLED
			return Self(directories: dirs,
						files: files,
						symlinks: symlinks,
						specials: specials)
		#else
			return Self(directories: dirs,
						files: files,
						symlinks: symlinks)
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
					#if SPECIALS_ENABLED
						case .special:
							self.specials.append(Special(uncheckedAt: resolvable.path, in: resolvable.fs.asInterface))
					#endif
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
		#if FINDER_ALIASES_ENABLED
			let base: some Sequence<any Node> = chain(chain(chain(self.directories, self.files), self.symlinks), self.specials)
			return chain(base, self.finderAliases)
		#elseif SPECIALS_ENABLED
			return chain(chain(chain(self.directories, self.files), self.symlinks), self.specials)
		#else
			return chain(chain(self.directories, self.files), self.symlinks)
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
		#if FINDER_ALIASES_ENABLED
			return baseEmpty && self.specials.isEmpty && self.finderAliases.isEmpty
		#elseif SPECIALS_ENABLED
			return baseEmpty && self.specials.isEmpty
		#else
			return baseEmpty
		#endif
	}

	public var count: Int {
		let baseCount = self.directories.count + self.files.count + self.symlinks.count
		#if FINDER_ALIASES_ENABLED
			return baseCount + self.specials.count + self.finderAliases.count
		#elseif SPECIALS_ENABLED
			return baseCount + self.specials.count
		#else
			return baseCount
		#endif
	}
}
