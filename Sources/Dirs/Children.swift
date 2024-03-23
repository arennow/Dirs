import Algorithms

public struct Children {
	static var empty: Self { .init(directories: [], files: []) }

	let directories: Array<Dir>
	let files: Array<File>

	init(directories: consuming Array<Dir>, files: consuming Array<File>) {
		self.directories = directories
		self.files = files
	}

	var all: some Sequence<any Node> {
		chain(self.directories, self.files)
	}
}
