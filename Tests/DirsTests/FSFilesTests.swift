import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func createFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let subDir = try fs.createDir(at: "/a")
		let createdFile = try subDir.createFile(at: "file")

		#expect(createdFile.path == "/a/file")
		#expect(throws: Never.self) { try fs.file(at: "/a/file") }
		try #expect(createdFile.contents() == Data())
		try #expect(fs.contentsOf(file: "/a/file") == Data())
	}

	@Test(arguments: FSKind.allCases)
	func createExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("content")

		let root = try fs.rootDir
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		try #expect(fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func createFileAtExistingDirFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a")

		let root = try fs.dir(at: "/")
		#expect(throws: (any Error).self) { try root.createFile(at: "a") }
		#expect(fs.nodeType(at: "/a") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func createFileThroughBrokenSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createSymlink(at: "/s", to: "/a")
		#expect(throws: (any Error).self) { try fs.createFile(at: "/s") }
	}

	@Test(arguments: FSKind.allCases)
	func createFileThroughFileSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")
		try fs.createSymlink(at: "/s", to: "/a")
		#expect(throws: (any Error).self) { try fs.createFile(at: "/s") }
	}

	@Test(arguments: FSKind.allCases)
	func createFileThroughDirSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createSymlink(at: "/s", to: "/d")
		#expect(throws: (any Error).self) { try fs.createFile(at: "/s") }
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsOfFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.rootDir.createFile(at: "a")
		try #expect(file.stringContents() == "")

		try file.replaceContents("content")
		try #expect(file.stringContents() == "content")

		try file.replaceContents("new content")
		try #expect(file.stringContents() == "new content")

		try file.replaceContents("smol")
		try #expect(file.stringContents() == "smol")
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsOfFileThroughFileSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let a = try fs.createFile(at: "/a")
		try fs.createSymlink(at: "/s", to: "/a")

		try fs.replaceContentsOfFile(at: "/s", to: "abc")
		try #expect(a.stringContents() == "abc")
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsOfFileThroughDirSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createSymlink(at: "/s", to: "/d")
		#expect(throws: (any Error).self) { try fs.replaceContentsOfFile(at: "/s", to: "abc") }
	}

	@Test(arguments: FSKind.allCases)
	func appendContentsOfFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.appendContents(" is king")
		try #expect(file.stringContents() == "content is king")
	}

	@Test(arguments: FSKind.allCases)
	func fileSizeEmpty(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/empty")
		try #expect(file.size() == 0)
	}

	@Test(arguments: FSKind.allCases)
	func fileSizeAfterReplace(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/file")
		try file.replaceContents("initial")
		try #expect(file.size() == 7)

		try file.replaceContents("much longer content")
		try #expect(file.size() == 19)

		try file.replaceContents("sm")
		try #expect(file.size() == 2)
	}

	@Test(arguments: FSKind.allCases)
	func fileSizeThroughSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/target")
		try file.replaceContents("target content")
		try fs.createSymlink(at: "/link", to: "/target")

		let linkSize = try fs.sizeOfFile(at: "/link")
		let fileSize = try file.size()
		#expect(linkSize == fileSize)
		#expect(linkSize == 14)
	}

	@Test(arguments: FSKind.allCases)
	func fileSizeOnDirectoryThrows(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/dir")

		#expect(throws: WrongNodeType.self) {
			try fs.sizeOfFile(at: "/dir")
		}
	}

	@Test(arguments: FSKind.allCases)
	func fileSizeOnNonexistentThrows(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		#expect(throws: NoSuchNode.self) {
			try fs.sizeOfFile(at: "/nonexistent")
		}
	}

	@Test(arguments: FSKind.allCases)
	func fileParent(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let a = try fs.createFile(at: "/a")

		#expect(try a.parent == fs.rootDir)
		#expect(try a.parent.parent == fs.rootDir)
	}
}
