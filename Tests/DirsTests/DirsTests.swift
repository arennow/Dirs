import Dirs
import DirsMockFSInterface
import Foundation
import SortAndFilter
import SystemPackage
import Testing

struct DirsTests {
	let fs: any FilesystemInterface = MockFilesystemInterface.empty()

	@Test func basicFSReading() throws {
		try self.fs.createFile(at: "/a")
		try self.fs.createFile(at: "/b")
		try self.fs.createFile(at: "/c").replaceContents("c content")
		try self.fs.createDir(at: "/d")
		try self.fs.createFile(at: "/d/E").replaceContents("enough!")
		try self.fs.createDir(at: "/f")

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

	@Test func subgraphFinding() throws {
		try self.fs.createFile(at: "/a1")
		try self.fs.createDir(at: "/a2")
		try self.fs.createDir(at: "/a3")
		try self.fs.createDir(at: "/a3/a3b1")
		try self.fs.createDir(at: "/a4")
		try self.fs.createDir(at: "/a4/a4b1")
		try self.fs.createFile(at: "/a4/a4b1/a4b1c1")

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

	@Test func createDir() throws {
		let created = try fs.createDir(at: "/a/b/c/d")

		#expect(throws: Never.self) { try Dir(fs: fs, path: "/a") }
		#expect(try Dir(fs: self.fs, path: "/a/b/c/d") == created)

		#expect(throws: Never.self) { try fs.createDir(at: "/a/b/c/d") }
	}

	@Test func createIntermediateDirs() throws {
		try self.fs.createDir(at: "/a/b")
		try self.fs.createDir(at: "/a/b/c/d/e")

		#expect(self.fs.nodeType(at: "/a/b/c") == .dir)
		#expect(self.fs.nodeType(at: "/a/b/c/d") == .dir)
		#expect(self.fs.nodeType(at: "/a/b/c/d/e") == .dir)
	}

	@Test func createExistingDir() throws {
		try self.fs.createDir(at: "/a")

		#expect(throws: Never.self) { try fs.createDir(at: "/a") }
	}

	@Test func dirOverExistingFileFails() throws {
		try self.fs.createFile(at: "/a")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a") }
	}

	@Test func createIntermediateDirsOverExistingFileFails() throws {
		try self.fs.createFile(at: "/a").replaceContents("content")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a/b") }
		#expect(try self.fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test func createFile() throws {
		let subDir = try fs.createDir(at: "/a")
		let createdFile = try subDir.createFile(at: "file")

		#expect(createdFile.path == "/a/file")
		#expect(throws: Never.self) { try File(fs: fs, path: "/a/file") }
		#expect(try createdFile.contents() == Data())
		#expect(try self.fs.contentsOf(file: "/a/file") == Data())
	}

	@Test func createExistingFileFails() throws {
		try self.fs.createFile(at: "/a").replaceContents("content")

		let root = try Dir(fs: fs, path: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(try self.fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test func createFileAtExistingDirFails() throws {
		try self.fs.createDir(at: "/a")

		let root = try Dir(fs: fs, path: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(self.fs.nodeType(at: "/a") == .dir)
	}

	@Test func replaceContentsOfFile() throws {
		try self.fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.replaceContents("new content")
		#expect(try file.stringContents() == "new content")
	}

	@Test func appendContentsOfFile() throws {
		try self.fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.appendContents(" is king")
		#expect(try file.stringContents() == "content is king")
	}

	@Test func deleteNode() throws {
		try self.fs.createFile(at: "/a")
		try self.fs.createFile(at: "/b")
		try self.fs.createFile(at: "/c").replaceContents("c content")
		try self.fs.createDir(at: "/d")
		try self.fs.createFile(at: "/d/E").replaceContents("enough!")
		try self.fs.createDir(at: "/f")

		try self.fs.deleteNode(at: "/a")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/a") }

		try self.fs.deleteNode(at: "/d")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/d/E") }
	}

	@Test func deleteNonexistentNodeFails() {
		#expect(throws: (any Error).self) { try fs.deleteNode(at: "/a") }
	}

	@Test func fileParent() throws {
		try self.fs.createFile(at: "/a")

		#expect(try self.fs.file(at: "/a").parent == self.fs.rootDir)
	}

	@Test func createFileAndIntermediaryDirs() throws {
		_ = try self.fs.createFileAndIntermediaryDirs(at: "/a/b/c/d/file1", contents: "contents 1")
		#expect(try self.fs.contentsOf(file: "/a/b/c/d/file1") == "contents 1".into())

		_ = try self.fs.createFileAndIntermediaryDirs(at: "/file2", contents: "contents 2")
		#expect(try self.fs.contentsOf(file: "/file2") == "contents 2".into())
	}

	@Test(arguments: ["/new", "/existing"])
	func dirInitWithCreation(path: FilePath) throws {
		try self.fs.createDir(at: "/existing")

		let firstTime = try Dir(fs: fs, path: path, createIfNeeded: true)
		let secondTime = try fs.dir(at: path)
		#expect(firstTime == secondTime)
	}

	@Test func dirInitNonExisting() {
		#expect(throws: (any Error).self) {
			try Dir(fs: fs, path: "/a")
		}
	}
}

// MARK: - Moves

extension DirsTests {
	@Test func moveNonexistentSourceFails() {
		#expect(throws: (any Error).self) {
			try fs.moveNode(from: "/a", to: "/b", replacingExisting: true)
		}
	}

	@Test func moveFileRenames() throws {
		try self.fs.rootDir.createFile(at: "c").replaceContents("c content")

		try self.fs.moveNode(from: "/c", to: "/X", replacingExisting: true)
		#expect(try self.fs.file(at: "/X").stringContents() == "c content")
		#expect(self.fs.nodeType(at: "/c") == nil)
	}

	@Test func moveFileReplaces() throws {
		try self.fs.rootDir.createFile(at: "c").replaceContents("c content")
		try self.fs.rootDir.createFile(at: "d")

		try self.fs.moveNode(from: "/c", to: "/d", replacingExisting: true)
		#expect(try self.fs.file(at: "/d").stringContents() == "c content")
		#expect(self.fs.nodeType(at: "/c") == nil)
	}

	@Test func moveFileDoesntReplace() throws {
		try self.fs.rootDir.createFile(at: "c").replaceContents("c content")
		try self.fs.rootDir.createFile(at: "d")

		#expect(throws: (any Error).self) { try fs.moveNode(from: "/c", to: "/d", replacingExisting: false) }
		#expect(try self.fs.file(at: "/c").stringContents() == "c content")
		#expect(try self.fs.file(at: "/d").contents() == Data())
	}

	@Test func moveFileChangesDir() throws {
		try self.fs.rootDir.createFile(at: "c").replaceContents("c content")
		try self.fs.rootDir.createDir(at: "d")

		try self.fs.moveNode(from: "/c", to: "/d", replacingExisting: true)
		#expect(try self.fs.file(at: "/d/c").stringContents() == "c content")
		#expect(self.fs.nodeType(at: "/c") == nil)
	}

	@Test func moveDirRenames() throws {
		try self.fs.rootDir.createDir(at: "d").createFile(at: "a").replaceContents("a content")

		try self.fs.moveNode(from: "/d", to: "/e", replacingExisting: true)
		#expect(try self.fs.file(at: "/e/a").stringContents() == "a content")
		#expect(self.fs.nodeType(at: "/d") == nil)
		#expect(self.fs.nodeType(at: "/d/a") == nil)
	}

	@Test func moveDirToFileFails() throws {
		try self.fs.rootDir.createFile(at: "a")
		try self.fs.rootDir.createDir(at: "d")

		#expect(throws: (any Error).self) { try fs.moveNode(from: "/d", to: "/a", replacingExisting: true) }
	}

	@Test(arguments: [true, false])
	func moveDirToDirIsRecursive(replacingExisting: Bool) throws {
		try self.fs.createDir(at: "/d")
		try self.fs.createFile(at: "/d/a").replaceContents("a")
		try self.fs.createDir(at: "/d/b")
		try self.fs.createFile(at: "/d/b/c").replaceContents("c")
		try self.fs.createDir(at: "/e")

		try self.fs.moveNode(from: "/d", to: "/e", replacingExisting: replacingExisting)
		#expect(try self.fs.file(at: "/e/d/a").stringContents() == "a")
		#expect(try self.fs.file(at: "/e/d/b/c").stringContents() == "c")
		#expect(self.fs.nodeType(at: "/d") == nil)
	}
}

extension DirsTests {
	@Test func randomPathDiffers() {
		#expect(self.fs.filePathOfNonexistentTemporaryFile() != self.fs.filePathOfNonexistentTemporaryFile())
	}

	@Test func randomPathHasExtension() {
		#expect(self.fs.filePathOfNonexistentTemporaryFile(extension: "abcd").string.hasSuffix("abcd"))
		#expect(self.fs.filePathOfNonexistentTemporaryFile(extension: ".abcd.").string.hasSuffix("abcd"))
	}
}
