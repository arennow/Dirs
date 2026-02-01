import Dirs
import Foundation
import SortAndFilter
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func renameNonexistentSourceFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(throws: (any Error).self) {
			try fs.renameNode(at: "/nope", to: "/dest")
		}
	}

	@Test(arguments: FSKind.allCases)
	func renameFileToAbsoluteFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var file = try fs.rootDir.createFile(at: "a")
		#expect(throws: InvalidPathForCall.needSingleComponent) {
			try file.rename(to: "b/c")
		}
	}

	@Test(arguments: FSKind.allCases)
	func renameFileWithMultipleComponents(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var file = try fs.rootDir.createFile(at: "a")
		#expect(throws: InvalidPathForCall.needSingleComponent) {
			try file.rename(to: "/b")
		}
	}

	@Test(arguments: FSKind.allCases)
	func renameFileToNewPathSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var file = try fs.rootDir.createFile(at: "a")
		try file.replaceContents("hello")
		try file.rename(to: "b")

		try #expect(fs.file(at: "/b").stringContents() == "hello")
		#expect(fs.nodeType(at: "/a") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func renameDirToNewPathSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var dir = try fs.rootDir.createDir(at: "dir1")
		try dir.createFile(at: "file").replaceContents("world")
		try dir.rename(to: "dir2")

		try #expect(fs.file(at: "/dir2/file").stringContents() == "world")
		#expect(fs.nodeType(at: "/dir1") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func renameSymlinkFileToNewPathSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "target").replaceContents("data")
		var symlink = try fs.rootDir.createSymlink(at: "link", to: "/target")

		try symlink.rename(to: "linkRenamed")

		try #expect(fs.destinationOf(symlink: "/linkRenamed") == "/target")
		#expect(fs.nodeType(at: "/link") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func renameSymlinkDirToNewPathSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createDir(at: "dirTarget").createFile(at: "f").replaceContents("x")
		var symlink = try fs.rootDir.createSymlink(at: "dirLink", to: "/dirTarget")

		try symlink.rename(to: "renamedLink")

		try #expect(fs.destinationOf(symlink: "/renamedLink") == "/dirTarget")
		#expect(fs.nodeType(at: "/dirLink") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func renameFailsWhenDestinationExists(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		// file→file conflict
		var src = try fs.rootDir.createFile(at: "src")
		try src.replaceContents("x")
		try fs.rootDir.createFile(at: "dest")
		#expect(throws: NodeAlreadyExists.self) {
			try src.rename(to: "dest")
		}

		// dir→dir conflict
		var d1 = try fs.rootDir.createDir(at: "d1")
		try fs.rootDir.createDir(at: "d2")
		#expect(throws: NodeAlreadyExists.self) {
			try d1.rename(to: "d2")
		}

		// file→dir conflict
		var f = try fs.rootDir.createFile(at: "f")
		try fs.rootDir.createDir(at: "d3")
		#expect(throws: NodeAlreadyExists.self) {
			try f.rename(to: "d3")
		}

		// dir→file conflict
		var d4 = try fs.rootDir.createDir(at: "d4")
		try fs.rootDir.createFile(at: "f2")
		#expect(throws: NodeAlreadyExists.self) {
			try d4.rename(to: "f2")
		}

		// file→symlink conflict
		var file1 = try fs.rootDir.createFile(at: "file1")
		try file1.replaceContents("a")
		try fs.rootDir.createFile(at: "targetFile")
		try fs.rootDir.createSymlink(at: "linkToFile", to: "/targetFile")
		#expect(throws: NodeAlreadyExists.self) {
			try file1.rename(to: "linkToFile")
		}

		// dir→symlink conflict
		var d = try fs.rootDir.createDir(at: "d")
		try fs.rootDir.createDir(at: "targetDir")
		try fs.rootDir.createSymlink(at: "linkToDir", to: "/targetDir")
		#expect(throws: NodeAlreadyExists.self) {
			try d.rename(to: "linkToDir")
		}
	}

	@Test(arguments: FSKind.allCases)
	func renameUpdatesReceiver(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var file = try fs.createFile(at: "/f1")
		try file.rename(to: "f2")

		#expect(file.path == "/f2")
	}
}
