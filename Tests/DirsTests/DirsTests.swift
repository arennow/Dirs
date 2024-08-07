@testable import Dirs
import DirsMockFSInterface
import SortAndFilter
import XCTest

final class DirsTests: XCTestCase {
	func testBasicFSReading() throws {
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

		XCTAssertEqual(childFileIterator.next()?.path, "/a")
		XCTAssertEqual(childFileIterator.next()?.path, "/b")

		let cFile = try XCTUnwrap(childFileIterator.next())
		XCTAssertEqual(cFile.path, "/c")
		XCTAssertEqual(try cFile.stringContents(), "c content")

		XCTAssertNil(childFileIterator.next())

		var childDirIterator = children.directories
			.sorted(by: Sort.asc(\.path.string))
			.makeIterator()

		let dDir = childDirIterator.next()
		XCTAssertEqual(dDir?.path, "/d")
		XCTAssertEqual(try dDir?.children().files.first?.stringContents(), "enough!")

		XCTAssertEqual(childDirIterator.next()?.path, "/f")
		XCTAssertNil(childDirIterator.next())
	}

	func testSubgraphFinding() throws {
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

		XCTAssertNotNil(d.childFile(named: "a1"))
		// Make sure we don't just support literals ⬇️
		XCTAssertNotNil(d.childFile(named: "a1" as String))
		XCTAssertNil(d.childFile(named: "a2"))
		XCTAssertNil(d.childFile(named: "a3"))
		XCTAssertNil(d.childFile(named: "a4"))

		XCTAssertNil(d.childDir(named: "a1"))
		// Make sure we don't just support literals ⬇️
		XCTAssertNil(d.childDir(named: "a1" as String))
		XCTAssertNotNil(d.childDir(named: "a2"))
		XCTAssertNotNil(d.childDir(named: "a3"))
		XCTAssertNotNil(d.childDir(named: "a4"))

		XCTAssertNotNil(d.descendentFile(at: "a1"))
		XCTAssertNil(d.descendentFile(at: "a2"))
		XCTAssertNil(d.descendentFile(at: "a3"))
		XCTAssertNil(d.descendentFile(at: "a4"))
		XCTAssertNotNil(d.descendentFile(at: "a4/a4b1/a4b1c1"))

		XCTAssertNil(d.descendentDir(at: "a1"))
		XCTAssertNotNil(d.descendentDir(at: "a2"))
		XCTAssertNotNil(d.descendentDir(at: "a3"))
		XCTAssertNotNil(d.descendentDir(at: "a4"))
		XCTAssertNotNil(d.descendentDir(at: "a4/a4b1"))
		XCTAssertNil(d.descendentDir(at: "a4/a4b1/a4b1c1"))
	}

	func testCreateDir() throws {
		let fs = MockFilesystemInterface.empty()
		let created = try fs.createDir(at: "/a/b/c/d")

		XCTAssertNoThrow(try Dir(fs: fs, path: "/a"))
		XCTAssertEqual(try Dir(fs: fs, path: "/a/b/c/d"), created)

		XCTAssertNoThrow(try fs.createDir(at: "/a/b/c/d"))
	}

	func testCreateIntermediateDirs() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a/b/c": .dir,
		])

		try fs.createDir(at: "/a/b/c/d/e")
		XCTAssertEqual(fs.nodeType(at: "/a/b/c"), .dir)
		XCTAssertEqual(fs.nodeType(at: "/a/b/c/d"), .dir)
		XCTAssertEqual(fs.nodeType(at: "/a/b/c/d/e"), .dir)
	}

	func testCreateExistingDir() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .dir,
		])

		XCTAssertNoThrow(try fs.createDir(at: "/a"))
	}

	func testDirOverExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
		])

		XCTAssertThrowsError(try fs.createDir(at: "/a"))
	}

	func testCreateIntermediateDirsOverExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		XCTAssertThrowsError(try fs.createDir(at: "/a/b"))
		XCTAssertEqual(try fs.contentsOf(file: "/a"), Data("content".utf8))
	}

	func testCreateFile() throws {
		let fs = MockFilesystemInterface.empty()
		let subDir = try fs.createDir(at: "/a")

		let createdFile = try subDir.createFile(at: "file")

		XCTAssertEqual(createdFile.path, "/a/file")
		XCTAssertNoThrow(try File(fs: fs, path: "/a/file"))
		XCTAssertEqual(try createdFile.contents(), Data())
		XCTAssertEqual(try fs.contentsOf(file: "/a/file"), Data())
	}

	func testCreateExistingFileFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let root = try Dir(fs: fs, path: "/")
		XCTAssertThrowsError(try root.createFile(at: "a"))
		XCTAssertEqual(try fs.contentsOf(file: "/a"), Data("content".utf8))
	}

	func testCreateFileAtExistingDirFails() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .dir,
		])

		let root = try Dir(fs: fs, path: "/")
		XCTAssertThrowsError(try root.createFile(at: "a"))
		XCTAssertEqual(fs.nodeType(at: "/a"), .dir)
	}

	func testReplaceContentsOfFile() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let file = try fs.file(at: "/a")
		try file.replaceContents("new content")
		XCTAssertEqual(try file.stringContents(), "new content")
	}

	func testAppendContentsOfFile() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file("content"),
		])

		let file = try fs.file(at: "/a")
		try file.appendContents(" is king")
		XCTAssertEqual(try file.stringContents(), "content is king")
	}

	func testDeleteNode() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
			"/b": .file,
			"/c": .file("c content"),
			"/d": .dir,
			"/d/E": .file("enough!"),
			"/f": .dir,
		])

		try mockFS.deleteNode(at: "/a")
		XCTAssertThrowsError(try mockFS.contentsOf(file: "/a"))

		try mockFS.deleteNode(at: "/d")
		XCTAssertThrowsError(try mockFS.contentsOf(file: "/d/E"))
	}

	func testFileParent() throws {
		let fs = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
		])

		try XCTAssertEqual(fs.file(at: "/a").parent, fs.rootDir)
	}

	func testCreateFileAndIntermediaryDirs() throws {
		let fs = MockFilesystemInterface()
		_ = try fs.createFileAndIntermediaryDirs(at: "/a/b/c/d/file1", contents: "contents 1")
		XCTAssertEqual(try fs.contentsOf(file: "/a/b/c/d/file1"), "contents 1".into())

		_ = try fs.createFileAndIntermediaryDirs(at: "/file2", contents: "contents 2")
		XCTAssertEqual(try fs.contentsOf(file: "/file2"), "contents 2".into())
	}
}

// MARK: - Moves

extension DirsTests {
	func testMoveNonexistantSourceFails() {
		let mockFS = MockFilesystemInterface()
		XCTAssertThrowsError(try mockFS.moveNode(from: "/a", to: "/b", replacingExisting: true))
	}

	func testMoveFileRenames() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
		])

		try mockFS.moveNode(from: "/c", to: "/X", replacingExisting: true)
		XCTAssertEqual(try mockFS.file(at: "/X").stringContents(), "c content")
		XCTAssertNil(mockFS.nodeType(at: "/c"))
	}

	func testMoveFileReplaces() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .file,
		])

		try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: true)
		XCTAssertEqual(try mockFS.file(at: "/d").stringContents(), "c content")
		XCTAssertNil(mockFS.nodeType(at: "/c"))
	}

	func testMoveFileDoesntReplace() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .file,
		])

		XCTAssertThrowsError(try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: false))
		XCTAssertEqual(try mockFS.file(at: "/c").stringContents(), "c content")
		XCTAssertEqual(try mockFS.file(at: "/d").contents(), Data())
	}

	func testMoveFileChangesDir() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/c": .file("c content"),
			"/d": .dir,
		])

		try mockFS.moveNode(from: "/c", to: "/d", replacingExisting: true)
		XCTAssertEqual(try mockFS.file(at: "/d/c").stringContents(), "c content")
		XCTAssertNil(mockFS.nodeType(at: "/c"))
	}

	func testMoveDirRenames() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/d": .dir,
			"/d/a": .file("a content"),
		])

		try mockFS.moveNode(from: "/d", to: "/e", replacingExisting: true)
		XCTAssertEqual(try mockFS.file(at: "/e/a").stringContents(), "a content")
		XCTAssertNil(mockFS.nodeType(at: "/d"))
		XCTAssertNil(mockFS.nodeType(at: "/d/a"))
	}

	func testMoveDirToFileFails() {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/a": .file,
			"/d": .dir,
		])

		XCTAssertThrowsError(try mockFS.moveNode(from: "/d", to: "/a", replacingExisting: true))
	}

	func testMoveDirToDirIsRecursive() throws {
		for re in [true, false] {
			let mockFS = MockFilesystemInterface(pathsToNodes: [
				"/d": .dir,
				"/d/a": .file("a"),
				"/d/b": .dir,
				"/d/b/c": .file("c"),
				"/e": .dir,
			])

			try mockFS.moveNode(from: "/d", to: "/e", replacingExisting: re)
			XCTAssertEqual(try mockFS.file(at: "/e/d/a").stringContents(), "a")
			XCTAssertEqual(try mockFS.file(at: "/e/d/b/c").stringContents(), "c")
			XCTAssertNil(mockFS.nodeType(at: "/d"))
		}
	}
}

extension DirsTests {
	func testRandomPathDiffers() {
		let fs = MockFilesystemInterface()

		XCTAssertNotEqual(fs.filePathOfNonexistantTemporaryFile(), fs.filePathOfNonexistantTemporaryFile())
	}

	func testRandomPathHasExtension() {
		let fs = MockFilesystemInterface()

		XCTAssert(fs.filePathOfNonexistantTemporaryFile(extension: "abcd").string.hasSuffix("abcd"))
		XCTAssert(fs.filePathOfNonexistantTemporaryFile(extension: ".abcd.").string.hasSuffix("abcd"))
	}
}
