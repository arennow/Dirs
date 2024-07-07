@testable import Dirs
import DirsMockFSInterface
import SortAndFilter
import XCTest

final class DirsTests: XCTestCase {
	func testMockFS() throws {
		let mockFS = MockFilesystemInterface(pathsToNodes: [
			"/": .dir,
			"/a": .file,
			"/b": .file,
			"/c": .file(Data("c content".utf8)),
			"/d": .dir,
			"/d/E": .file(Data("enough!".utf8)),
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
			"/": .dir,
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

	func testCreateFile() throws {
		let fs = MockFilesystemInterface.empty()
		let subDir = try fs.createDir(at: "/a")

		let createdFile = try subDir.createFile(at: "file")

		XCTAssertEqual(createdFile.path, "/a/file")
		XCTAssertNoThrow(try File(fs: fs, path: "/a/file"))
	}
}
