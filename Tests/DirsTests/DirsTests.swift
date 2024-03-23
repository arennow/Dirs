@testable import Dirs
import XCTest

final class DirsTests: XCTestCase {
	func testExample() throws {
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
}
