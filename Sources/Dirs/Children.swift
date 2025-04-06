import Algorithms

public struct Children {
	static var empty: Self { .init(directories: [], files: []) }

	public let directories: Array<Dir>
	public let files: Array<File>

	init(directories: consuming Array<Dir>, files: consuming Array<File>) {
		self.directories = directories
		self.files = files
	}

	var all: some Sequence<any Node> {
		chain(self.directories, self.files)
	}

	var isEmpty: Bool {
		self.directories.isEmpty && self.files.isEmpty
	}
}
