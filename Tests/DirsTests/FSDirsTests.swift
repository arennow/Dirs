import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func createDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let created = try fs.createDir(at: "/a/b/c/d")

		#expect(throws: Never.self) { try fs.dir(at: "/a") }
		try #expect(fs.dir(at: "/a/b/c/d") == created)
	}

	@Test(arguments: FSKind.allCases)
	func createIntermediateDirs(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a/b")
		try fs.createDir(at: "/a/b/c/d/e")

		#expect(fs.nodeType(at: "/a/b/c") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d") == .dir)
		#expect(fs.nodeType(at: "/a/b/c/d/e") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func createRootDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		#expect(throws: NodeAlreadyExists.self) { try fs.createDir(at: "/") }
	}

	@Test(arguments: FSKind.allCases)
	func dirOverExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a") }
	}

	@Test(arguments: FSKind.allCases)
	func createIntermediateDirsOverExistingFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("content")

		#expect(throws: (any Error).self) { try fs.createDir(at: "/a/b") }
		try #expect(fs.contentsOf(file: "/a") == Data("content".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func dirInitNonExisting(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: NoSuchNode(path: "/a")) {
			try fs.dir(at: "/a")
		}
	}

	@Test(arguments: FSKind.allCases)
	func dirIsAncestorOfNode(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let symlinks = try Self.prepareForSymlinkTests(fs)

		let d = try fs.dir(at: "/d")
		let descFile = try fs.file(at: "/d/d1")
		let descDir = try fs.dir(at: "/d/e")

		#expect(try d.isAncestor(of: descFile))
		#expect(try d.isAncestor(of: descDir))
		#expect(try symlinks.dir.isAncestor(of: descFile))
		#expect(try symlinks.dir.isAncestor(of: descDir))
		#expect(try symlinks.dirSym.isAncestor(of: descFile))
		#expect(try symlinks.dirSym.isAncestor(of: descDir))
	}

	@Test(arguments: FSKind.allCases)
	func ensureInDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var a = try fs.createFile(at: "/a")
		let d = try fs.createDir(at: "/d")

		try a.ensure(in: d)
		#expect(a.path == "/d/a")
		#expect(d.allDescendantFiles().map(\.name) == ["a"])

		try a.ensure(in: d)
		#expect(a.path == "/d/a")
		#expect(d.allDescendantFiles().map(\.name) == ["a"])
	}
}
