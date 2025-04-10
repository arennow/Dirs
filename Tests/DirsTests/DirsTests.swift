@testable import Dirs
import DirsMockFSInterface
import Foundation
import SortAndFilter
import Testing

struct DirsTests {
	@Test func basicFSReading() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
			"/b": .file,
			"/c": .file("c content"),
			"/d": .dir,
			"/d/E": .file("enough!"),
			"/f": .dir,
		])

		let children = try mockFS.rootDir.children()
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
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a1": .file,
			"/a2": .dir,
			"/a3": .dir,
			"/a3/a3b1": .file,
			"/a4": .dir,
			"/a4/a4b1": .dir,
			"/a4/a4b1/a4b1c1": .file,
		])

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
		let fs = MockFilesystemInterface.empty()
		let created = try fs.createDir(at: "/a/b/c/d")

		#expect(throws: Never.self) { try Dir(fs: fs, path: "/a") }
		#expect(try Dir(fs: fs, path: "/a/b/c/d") == created)

		#expect(throws: Never.self) { try fs.createDir(at: "/a/b/c/d") }
	}

	@Test func createIntermediateDirs() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a/b/c": .dir,
		])

		try fs.createDir(at: "/a/b/c/d/e")
		#expect(fs.nodeType(at: "/a/b/c") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d/e") == .dir)
	}

	@Test func createExistingDir() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .dir,
		])

		#expect(throws: Never.self) { try fs.createDir(at: "/a") }
	}

	@Test func dirOverExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
		])

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a") }
	}

	@Test func createIntermediateDirsOverExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a/b") }
		#expect(try fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test func createFile() throws {
		let fs = MockFilesystemInterface.empty()
		let subDir = try fs.createDir(at: "/a")

		let createdFile = try subDir.createFile(at: "file")

		#expect(createdFile.path == "/a/file")
		#expect(throws: Never.self) { try File(fs: fs, path: "/a/file") }
		#expect(try createdFile.contents() == Data())
		#expect(try fs.contentsOf(file: "/a/file") == Data())
	}

	@Test func createExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let root = try Dir(fs: fs, path: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(try fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test func createFileAtExistingDirFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .dir,
		])

		let root = try Dir(fs: fs, path: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(fs.nodeType(at: "/a") == .dir)
	}

	@Test func replaceContentsOfFile() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let file = try fs.file(at: "/a")
		try file.replaceContents("new content")
		#expect(try file.stringContents() == "new content")
	}

	@Test func appendContentsOfFile() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let file = try fs.file(at: "/a")
		try file.appendContents(" is king")
		#expect(try file.stringContents() == "content is king")
	}

	@Test func deleteNode() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
			"/b": .file,
			"/c": .file("c content"),
			"/d": .dir,
			"/d/E": .file("enough!"),
			"/f": .dir,
		])

		try mockFS.deleteNode(at: "/a")
		#expect(throws: (any Error).self) { try mockFS.contentsOf(file: "/a") }

		try mockFS.deleteNode(at: "/d")
		#expect(throws: (any Error).self) { try mockFS.contentsOf(file: "/d/E") }
	}

	@Test func fileParent() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
		])

		#expect(try fs.file(at: "/a").parent == fs.rootDir)
	}

	@Test func createFileAndIntermediaryDirs() throws {
		let fs = MockFilesystemInterface()
		_ = try fs.createFileAndIntermediaryDirs(at: "/a/b/c/d/file1", contents: "contents 1")
		#expect(try fs.contentsOf(file: "/a/b/c/d/file1") == "contents 1".into())

		_ = try fs.createFileAndIntermediaryDirs(at: "/file2", contents: "contents 2")
		#expect(try fs.contentsOf(file: "/file2") == "contents 2".into())
	}
}

// MARK: - Moves

extension DirsTests {
	@Test func moveNonexistantSourceFails() {
		let mockFS = MockFilesystemInterface()
		#expect(throws: (any Error).self) { try mockFS.moveNode(from: "/a", to: "/b", replacingExisting: true) }
	}

	@Test func moveFileRenames() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
		])

		try mockFS.moveNode(from: "/c", to: "/X", replacingExisting: true)
		#expect(try mockFS.file(at: "/X").stringContents() == "c content")
		#expect(mockFS.nodeType(at: "/c") == nil)
	}

	@Test func moveFileReplaces() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .file,
		])

		try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: true)
		#expect(try mockFS.file(at: "/d").stringContents() == "c content")
		#expect(mockFS.nodeType(at: "/c") == nil)
	}

	@Test func moveFileDoesntReplace() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .file,
		])

		#expect(throws: (any Error).self) { try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: false) }
		#expect(try mockFS.file(at: "/c").stringContents() == "c content")
		#expect(try mockFS.file(at: "/d").contents() == Data())
	}

	@Test func moveFileChangesDir() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .dir,
		])

		try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: true)
		#expect(try mockFS.file(at: "/d/c").stringContents() == "c content")
		#expect(mockFS.nodeType(at: "/c") == nil)
	}

	@Test func moveDirRenames() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/d": .dir,
			"/d/a": .file("a content"),
		])

		try mockFS.moveNode(from: "/d", to: "/e", replacingExisting: true)
		#expect(try mockFS.file(at: "/e/a").stringContents() == "a content")
		#expect(mockFS.nodeType(at: "/d") == nil)
		#expect(mockFS.nodeType(at: "/d/a") == nil)
	}

	@Test func moveDirToFileFails() {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
			"/d": .dir,
		])

		#expect(throws: (any Error).self) { try mockFS.moveNode(from: "/d", to: "/a", replacingExisting: true) }
	}

	@Test func moveDirToDirIsRecursive() throws {
		for re in [true, false] {
			let mockFS = MockFilesystemInterface(pathsToNodes: [
				"/d": .dir,
				"/d/a": .file("a"),
				"/d/b": .dir,
				"/d/b/c": .file("c"),
				"/e": .dir,
			])

			try mockFS.moveNode(from: "/d", to: "/e", replacingExisting: re)
			#expect(try mockFS.file(at: "/e/d/a").stringContents() == "a")
			#expect(try mockFS.file(at: "/e/d/b/c").stringContents() == "c")
			#expect(mockFS.nodeType(at: "/d") == nil)
		}
	}
}

extension DirsTests {
	@Test func randomPathDiffers() {
		let fs = MockFilesystemInterface()

		#expect(fs.filePathOfNonexistantTemporaryFile() != fs.filePathOfNonexistantTemporaryFile())
	}

	@Test func randomPathHasExtension() {
		let fs = MockFilesystemInterface()

		#expect(fs.filePathOfNonexistantTemporaryFile(extension: "abcd").string.hasSuffix("abcd"))
		#expect(fs.filePathOfNonexistantTemporaryFile(extension: ".abcd.").string.hasSuffix("abcd"))
	}
}
