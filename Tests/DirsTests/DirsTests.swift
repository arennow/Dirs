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
		let root = try Dir(fs: mockFS, path: "/")

		let children = try root.children()
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
		XCTAssertNil(d.childFile(named: "a2"))
		XCTAssertNil(d.childFile(named: "a3"))
		XCTAssertNil(d.childFile(named: "a4"))

		XCTAssertNil(d.childDir(named: "a1"))
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
}
