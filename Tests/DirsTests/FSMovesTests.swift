import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func moveNonexistentSourceFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			try fs.moveNode(from: "/a", to: "/b")
		}
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToNothingRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")

		try fs.moveNode(from: "/c", to: "/X")
		try #expect(fs.file(at: "/X").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createFile(at: "d")

		try fs.moveNode(from: "/c", to: "/d")
		try #expect(fs.file(at: "/d").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createDir(at: "d")

		try fs.moveNode(from: "/c", to: "/d")
		try #expect(fs.file(at: "/d/c").stringContents() == "c content")
		#expect(fs.nodeType(at: "/c") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToBrokenSymlinkReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createSymlink(at: "/s", to: "/Z")

		try fs.moveNode(from: "/c", to: "/s")
		try #expect(fs.file(at: "/s").stringContents() == "c content")

		#expect(fs.nodeType(at: "/c") == nil)
		#expect(fs.nodeType(at: "/s") == .file)
		#expect(fs.nodeType(at: "/Z") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToFileSymlinkReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "b").replaceContents("b content")
		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createSymlink(at: "/s", to: "/b")

		try fs.moveNode(from: "/c", to: "/s")
		try #expect(fs.file(at: "/s").stringContents() == "c content")

		#expect(fs.nodeType(at: "/b") == .file)
		#expect(fs.nodeType(at: "/c") == nil)
		#expect(fs.nodeType(at: "/s") == .file)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileToDirSymlinkRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createDir(at: "d")
		try fs.rootDir.createSymlink(at: "/s", to: "/d")

		try fs.moveNode(from: "/c", to: "/s")
		try #expect(fs.file(at: "/s/c").stringContents() == "c content")

		#expect(fs.nodeType(at: "/c") == nil)
		#expect(fs.nodeType(at: "/d") == .dir)
		#expect(fs.nodeType(at: "/s") == .symlink)
		#expect(fs.nodeType(at: "/s/c") == .file)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToNothingRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createDir(at: "d").createFile(at: "a").replaceContents("a content")

		try fs.moveNode(from: "/d", to: "/e")
		try #expect(fs.file(at: "/e/a").stringContents() == "a content")
		#expect(fs.nodeType(at: "/d") == nil)
		#expect(fs.nodeType(at: "/d/a") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a")
		try fs.rootDir.createDir(at: "d")

		try fs.moveNode(from: "/d", to: "/a")

		try #expect(fs.rootDir.dir(at: "d") == nil)
		try #expect(fs.rootDir.dir(at: "a") != nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/a").replaceContents("a")
		try fs.createDir(at: "/d/b")
		try fs.createFile(at: "/d/b/c").replaceContents("c")
		try fs.createDir(at: "/e")

		try fs.moveNode(from: "/d", to: "/e")
		try #expect(fs.file(at: "/e/d/a").stringContents() == "a")
		try #expect(fs.file(at: "/e/d/b/c").stringContents() == "c")
		#expect(fs.nodeType(at: "/d") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToBrokenSymlinkReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let d = try fs.rootDir.createDir(at: "d")
		try d.createFile(at: "a").replaceContents("d/a content")
		try fs.rootDir.createSymlink(at: "/s", to: "/Z")

		try fs.moveNode(from: "/d", to: "/s")
		try #expect(fs.file(at: "/s/a").stringContents() == "d/a content")

		#expect(fs.nodeType(at: "/s") == .dir)
		#expect(fs.nodeType(at: "/s/a") == .file)
		#expect(fs.nodeType(at: "/Z") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToFileSymlinkReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let d = try fs.rootDir.createDir(at: "d")
		try d.createFile(at: "a").replaceContents("d/a content")

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createSymlink(at: "/s", to: "/c")

		try fs.moveNode(from: "/d", to: "/s")
		try #expect(fs.file(at: "/s/a").stringContents() == "d/a content")

		#expect(fs.nodeType(at: "/c") == .file)
		#expect(fs.nodeType(at: "/s") == .dir)
		#expect(fs.nodeType(at: "/s/a") == .file)
	}

	@Test(arguments: FSKind.allCases)
	func moveDirToDirSymlinkRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let d1 = try fs.rootDir.createDir(at: "d1")
		try d1.createFile(at: "a1").replaceContents("a1 content")

		let d2 = try fs.rootDir.createDir(at: "d2")
		try d2.createFile(at: "a2").replaceContents("a2 content")

		try fs.rootDir.createSymlink(at: "/s", to: "/d2")

		try fs.moveNode(from: "/d1", to: "/s")

		#expect(fs.nodeType(at: "/d2") == .dir)
		#expect(fs.nodeType(at: "/d2/a2") == .file)
		try #expect(fs.file(at: "/d2/a2").stringContents() == "a2 content")
		#expect(fs.nodeType(at: "/d2/d1") == .dir)
		#expect(fs.nodeType(at: "/d2/d1/a1") == .file)
		try #expect(fs.file(at: "/d2/d1/a1").stringContents() == "a1 content")
		#expect(fs.nodeType(at: "/s") == .symlink)
	}

	@Test(arguments: FSKind.allCases)
	func moveSymlinkToNothingRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.moveNode(from: "/s", to: "/s2")
		#expect(fs.nodeType(at: "/s2") == .symlink)
		try #expect(fs.file(at: "/s2").stringContents() == "abc")
		#expect(fs.nodeType(at: "/s") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveSymlinkToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.moveNode(from: "/s", to: "/b")
		try #expect(fs.file(at: "/b").stringContents() == "abc")

		#expect(fs.nodeType(at: "/a") == .file)
		#expect(fs.nodeType(at: "/b") == .symlink)
		#expect(fs.nodeType(at: "/s") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveSymlinkToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.moveNode(from: "/s", to: "/d")
		try #expect(fs.file(at: "/d/s").stringContents() == "abc")

		#expect(fs.nodeType(at: "/a") == .file)
		#expect(fs.nodeType(at: "/d/s") == .symlink)
		#expect(fs.nodeType(at: "/s") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func moveFileUpdatesReceiverPath(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var file = try fs.createFile(at: "/f1")
		try file.replaceContents("content")

		try file.move(to: "/f2")

		#expect(file.path == "/f2")
		try #expect(file.stringContents() == "content")
		try #expect(fs.file(at: "/f2").stringContents() == "content")

		let d = try fs.createDir(at: "/d")
		try file.move(to: d)
		#expect(file.path == "/d/f2")
	}

	@Test(arguments: FSKind.allCases)
	func moveDirUpdatesReceiverPath(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var dir = try fs.createDir(at: "/d1")
		try dir.move(to: "/d2")
		#expect(dir.path == "/d2")

		let d = try fs.createDir(at: "/d")
		try dir.move(to: d)
		#expect(dir.path == "/d/d2")
	}

	@Test(arguments: FSKind.allCases)
	func moveSymlinkUpdatesReceiverPath(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		var (sym, _, _, _, _) = try Self.prepareForSymlinkTests(fs)

		try sym.move(to: "/s2")
		#expect(sym.path == "/s2")

		let d = try fs.dir(at: "/d")
		try sym.move(to: d)
		#expect(sym.path == "/d/s2")
	}

	#if canImport(Darwin) || os(Linux)
		@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
		func movePreservesExtendedAttributes(fsKind: FSKind, nodeType: NodeType) throws {
			#if os(Linux)
				// Linux kernel VFS prohibits user-namespaced xattrs on symlinks
				guard nodeType != .symlink else { return }
			#endif

			let fs = self.fs(for: fsKind)
			var (node, _) = try nodeType.createNode(at: "/source", in: fs)

			let originalXattrs = try node.extendedAttributeNames()
			try node.setExtendedAttribute(named: "user.test", to: "value")
			let expectedXattrs = originalXattrs.union(["user.test"])

			try node.move(to: "/dest")

			#expect(node.path == "/dest")
			let movedXattrs = try node.extendedAttributeNames()
			#expect(movedXattrs == expectedXattrs)
			#expect(try node.extendedAttributeString(named: "user.test") == "value")
			#expect(fs.nodeType(at: "/source") == nil)
		}
	#endif

	@Test(arguments: FSKind.allCases)
	func nodeMoveHandlesRelativePaths(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createDir(at: "parent")
		var file = try fs.rootDir.newOrExistingDir(at: "parent").createFile(at: "file.txt")
		try file.replaceContents("content")

		try file.move(to: "../moved.txt")

		#expect(file.path == "/moved.txt")
		try #expect(fs.file(at: "/moved.txt").stringContents() == "content")
		#expect(fs.nodeType(at: "/parent/file.txt") == nil)
	}
}
