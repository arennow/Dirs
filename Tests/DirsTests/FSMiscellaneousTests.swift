import Dirs
import Foundation
import SortAndFilter
import SystemPackage
import Testing

extension FSTests {
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
		try #expect(cFile.stringContents() == "c content")

		#expect(childFileIterator.next() == nil)

		var childDirIterator = children.directories
			.sorted(by: Sort.asc(\.path.string))
			.makeIterator()

		let dDir = childDirIterator.next()
		#expect(dDir?.path == "/d")
		try #expect(dDir?.children().files.first?.stringContents() == "enough!")

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

		let d = try fs.dir(at: "/")

		#expect(d.childFile(named: "a1") != nil)
		#expect(d.childFile(named: "a1" as String) != nil)
		#expect(d.childFile(named: "a2") == nil)
		#expect(d.childFile(named: "a3") == nil)
		#expect(d.childFile(named: "a4") == nil)

		#expect(d.childDir(named: "a1") == nil)
		#expect(d.childDir(named: "a1" as String) == nil)
		#expect(d.childDir(named: "a2") != nil)
		#expect(d.childDir(named: "a3") != nil)
		#expect(d.childDir(named: "a4") != nil)

		#expect(d.descendantFile(at: "a1") != nil)
		#expect(d.descendantFile(at: "a2") == nil)
		#expect(d.descendantFile(at: "a3") == nil)
		#expect(d.descendantFile(at: "a4") == nil)
		#expect(d.descendantFile(at: "a4/a4b1/a4b1c1") != nil)

		#expect(d.descendantDir(at: "a1") == nil)
		#expect(d.descendantDir(at: "a2") != nil)
		#expect(d.descendantDir(at: "a3") != nil)
		#expect(d.descendantDir(at: "a4") != nil)
		#expect(d.descendantDir(at: "a4/a4b1") != nil)
		#expect(d.descendantDir(at: "a4/a4b1/a4b1c1") == nil)
	}
}
