@testable import Dirs
import DirsMockFSInterface
import XCTest

final class DirsTests: XCTestCase {
	func testMockFS() throws {
		let mockFS = MockFilesystemInterface {
			"a"
			"b"
			("c", "c content")
			dir("d") {
				("E", "enough!")
			}
			dir("f")
		}
		let root = try Dir(fs: mockFS, path: "/")

		let children = try root.children()
		var childFileIterator = children.files.makeIterator()

		XCTAssertEqual(childFileIterator.next()?.path, "/a")
		XCTAssertEqual(childFileIterator.next()?.path, "/b")

		let cFile = try XCTUnwrap(childFileIterator.next())
		XCTAssertEqual(cFile.path, "/c")
		XCTAssertEqual(try cFile.stringContents(), "c content")

		XCTAssertNil(childFileIterator.next())

		var childDirIterator = children.directories.makeIterator()

		let dDir = childDirIterator.next()
		XCTAssertEqual(dDir?.path, "/d")
		XCTAssertEqual(try dDir?.children().files.first?.stringContents(), "enough!")

		XCTAssertEqual(childDirIterator.next()?.path, "/f")
		XCTAssertNil(childDirIterator.next())
	}

	func testSubgraphFinding() throws {
		let fs = MockFilesystemInterface {
			"a1"
			dir("a2")
			dir("a3") {
				"a3b1"
			}
			dir("a4") {
				dir("a4b1") {
					"a4b1c1"
				}
			}
		}

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
}
