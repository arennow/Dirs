import Dirs
import DirsMockFSInterface
import Foundation
import SortAndFilter
import SystemPackage
import Testing

struct DirsTests: ~Copyable {
	let mockFS: any FilesystemInterface = MockFilesystemInterface.empty()
	let realFS: any FilesystemInterface
	let pathToDelete: FilePath?

	init() throws {
		let realFS = try RealFSInterface(chroot: .temporaryUnique())
		self.pathToDelete = realFS.chroot
		self.realFS = realFS
	}

	deinit {
		guard let pathToDelete = self.pathToDelete else { return }
		try? FileManager.default.removeItem(at: pathToDelete.url)
	}

	enum FSKind: CaseIterable { case mock, real }

	private func fs(for kind: FSKind) -> any FilesystemInterface {
		switch kind {
			case .mock: self.mockFS
			case .real: self.realFS
		}
	}

	@Test(arguments: FSKind.allCases)
	func basicFSReading(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")
		try fs.createFile(at: "/b")
		try fs.createFile(at: "/c").replaceContents("c content")
		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/E").replaceContents("enough!")
		try fs.createDir(at: "/f")

		let children = try fs.rootDir.children()
		var childFileIterator = children.files
			.sorted(by: Sort.asc(\.path.string))
			.makeIterator()

		#expect(childFileIterator.next()?.path == "/a")
		#expect(childFileIterator.next()?.path == "/b")

		/*
		 This stupid indirection is due to the implicit autoclosure in the
		 expansion of #require not being able to handle a mutating function
		 */
		// swiftformat:disable:next redundantClosure
		let cFile = try #require({ childFileIterator.next() }())
		#expect(cFile.path == "/c")
		#expect(try cFile.stringContents() == "c content")

		#expect(childFileIterator.next() == nil)

		var childDirIterator = children.directories
			.sorted(by: Sort.asc(\.path.string))
			.makeIterator()

		let dDir = childDirIterator.next()
		#expect(dDir?.path == "/d")
		#expect(try dDir?.children().files.first?.stringContents() == "enough!")

		#expect(childDirIterator.next()?.path == "/f")
		#expect(childDirIterator.next() == nil)
	}

	@Test(arguments: FSKind.allCases)
	func subgraphFinding(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a1")
		try fs.createDir(at: "/a2")
		try fs.createDir(at: "/a3")
		try fs.createDir(at: "/a3/a3b1")
		try fs.createDir(at: "/a4")
		try fs.createDir(at: "/a4/a4b1")
		try fs.createFile(at: "/a4/a4b1/a4b1c1")

		let d = try Dir(fs: fs, path: "/")

		#expect(d.childFile(named: "a1") != nil)
		// Make sure we don't just support literals ⬇️
		#expect(d.childFile(named: "a1" as String) != nil)
		#expect(d.childFile(named: "a2") == nil)
		#expect(d.childFile(named: "a3") == nil)
		#expect(d.childFile(named: "a4") == nil)

		#expect(d.childDir(named: "a1") == nil)
		// Make sure we don't just support literals ⬇️
		#expect(d.childDir(named: "a1" as String) == nil)
		#expect(d.childDir(named: "a2") != nil)
		#expect(d.childDir(named: "a3") != nil)
		#expect(d.childDir(named: "a4") != nil)

		#expect(d.descendentFile(at: "a1") != nil)
		#expect(d.descendentFile(at: "a2") == nil)
		#expect(d.descendentFile(at: "a3") == nil)
		#expect(d.descendentFile(at: "a4") == nil)
		#expect(d.descendentFile(at: "a4/a4b1/a4b1c1") != nil)

		#expect(d.descendentDir(at: "a1") == nil)
		#expect(d.descendentDir(at: "a2") != nil)
		#expect(d.descendentDir(at: "a3") != nil)
		#expect(d.descendentDir(at: "a4") != nil)
		#expect(d.descendentDir(at: "a4/a4b1") != nil)
		#expect(d.descendentDir(at: "a4/a4b1/a4b1c1") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func createDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let created = try fs.createDir(at: "/a/b/c/d")

		#expect(throws: Never.self) { try Dir(fs: fs, path: "/a") }
		#expect(try Dir(fs: fs, path: "/a/b/c/d") == created)

		#expect(throws: Never.self) { try fs.createDir(at: "/a/b/c/d") }
	}

	@Test(arguments: FSKind.allCases)
	func createIntermediateDirs(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a/b")
		try fs.createDir(at: "/a/b/c/d/e")

		#expect(fs.nodeType(at: "/a/b/c") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d/e") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func createExistingDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a")

		#expect(throws: Never.self) { try fs.createDir(at: "/a") }
	}

	@Test(arguments: FSKind.allCases)
	func dirOverExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a") }
	}

	@Test(arguments: FSKind.allCases)
	func createIntermediateDirsOverExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("content")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a/b") }
		#expect(try fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func createFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let subDir = try fs.createDir(at: "/a")
		let createdFile = try subDir.createFile(at: "file")

		#expect(createdFile.path == "/a/file")
		#expect(throws: Never.self) { try File(fs: fs, path: "/a/file") }
		#expect(try createdFile.contents() == Data())
		#expect(try fs.contentsOf(file: "/a/file") == Data())
	}

	@Test(arguments: FSKind.allCases)
	func createExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("content")

		let root = try fs.rootDir
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(try fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func createFileAtExistingDirFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a")

		let root = try Dir(fs: fs, path: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(fs.nodeType(at: "/a") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsOfFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.replaceContents("new content")
		#expect(try file.stringContents() == "new content")
	}

	@Test(arguments: FSKind.allCases)
	func appendContentsOfFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.appendContents(" is king")
		#expect(try file.stringContents() == "content is king")
	}

	@Test(arguments: FSKind.allCases)
	func deleteNode(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")
		try fs.createFile(at: "/b")
		try fs.createFile(at: "/c").replaceContents("c content")
		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/E").replaceContents("enough!")
		try fs.createDir(at: "/f")

		try fs.deleteNode(at: "/a")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/a") }

		try fs.deleteNode(at: "/d")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/d/E") }
	}

	@Test(arguments: FSKind.allCases)
	func deleteNonexistentNodeFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(throws: (any Error).self) { try fs.deleteNode(at: "/a") }
	}

	@Test(arguments: FSKind.allCases)
	func fileParent(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")

		#expect(try fs.file(at: "/a").parent == fs.rootDir)
	}

	@Test(arguments: FSKind.allCases)
	func createFileAndIntermediaryDirs(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.createFileAndIntermediaryDirs(at: "/a/b/c/d/file1").replaceContents("contents 1")
		#expect(try fs.contentsOf(file: "/a/b/c/d/file1") == "contents 1".into())

		_ = try fs.createFileAndIntermediaryDirs(at: "/file2").replaceContents("contents 2")
		#expect(try fs.contentsOf(file: "/file2") == "contents 2".into())
	}

	@Test(arguments: FSKind.allCases, ["/new", "/existing"])
	func dirInitWithCreation(fsKind: FSKind, path: FilePath) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/existing")

		let firstTime = try Dir(fs: fs, path: path, createIfNeeded: true)
		let secondTime = try fs.dir(at: path)
		#expect(firstTime == secondTime)
	}

	@Test(arguments: FSKind.allCases)
	func dirInitNonExisting(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			try Dir(fs: fs, path: "/a")
		}
	}
}

// MARK: - Moves

extension DirsTests {
	@Test(arguments: FSKind.allCases)
	func moveNonexistentSourceFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			try fs.moveNode(from: "/a", to: "/b")
		}
	}

	@Test(arguments: FSKind.allCases)
	func moveFileRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")

		try fs.moveNode(from: "/c", to: "/X")
		#expect(try fs.file(at: "/X").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createFile(at: "d")

		try fs.moveNode(from: "/c", to: "/d")
		#expect(try fs.file(at: "/d").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileChangesDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createDir(at: "d")

		try fs.moveNode(from: "/c", to: "/d")
		#expect(try fs.file(at: "/d/c").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createDir(at: "d").createFile(at: "a").replaceContents("a content")

		try fs.moveNode(from: "/d", to: "/e")
		#expect(try fs.file(at: "/e/a").stringContents() == "a content")
		#expect(fs.nodeType(at: "/d") == nil)
		#expect(fs.nodeType(at: "/d/a") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a")
		try fs.rootDir.createDir(at: "d")

		try fs.moveNode(from: "/d", to: "/a")

		try #expect(fs.rootDir.childDir(named: "d") == nil)
		try #expect(fs.rootDir.childDir(named: "a") != nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToDirIsRecursive(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/a").replaceContents("a")
		try fs.createDir(at: "/d/b")
		try fs.createFile(at: "/d/b/c").replaceContents("c")
		try fs.createDir(at: "/e")

		try fs.moveNode(from: "/d", to: "/e")
		#expect(try fs.file(at: "/e/d/a").stringContents() == "a")
		#expect(try fs.file(at: "/e/d/b/c").stringContents() == "c")
		#expect(fs.nodeType(at: "/d") == nil)
	}
}

extension DirsTests {
	@Test(arguments: FSKind.allCases)
	func randomPathDiffers(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(fs.filePathOfNonexistentTemporaryFile() != fs.filePathOfNonexistentTemporaryFile())
	}

	@Test(arguments: FSKind.allCases)
	func randomPathHasExtension(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(fs.filePathOfNonexistentTemporaryFile(extension: "abcd").string.hasSuffix("abcd"))
		#expect(fs.filePathOfNonexistentTemporaryFile(extension: ".abcd.").string.hasSuffix("abcd"))
	}
}
