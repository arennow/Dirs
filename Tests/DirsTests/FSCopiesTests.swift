import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func copyNonexistentSourceFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			try fs.copyNode(from: "/a", to: "/b")
		}
	}

	@Test(arguments: FSKind.allCases)
	func copyFileToNothingDuplicates(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.rootDir.createFile(at: "a")
		try file.replaceContents("a content")
		try file.copy(to: "/b")
		try #expect(fs.file(at: "/b").stringContents() == "a content")
	}

	@Test(arguments: FSKind.allCases)
	func copyFileToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let fileC = try fs.rootDir.createFile(at: "c")
		try fileC.replaceContents("c content")
		try fs.rootDir.createFile(at: "d")

		try fileC.copy(to: "/d")

		try #expect(fs.file(at: "/c").stringContents() == "c content")
		try #expect(fs.file(at: "/d").stringContents() == "c content")
	}

	@Test(arguments: FSKind.allCases)
	func copyFileToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let fileC = try fs.rootDir.createFile(at: "c")
		try fileC.replaceContents("c content")
		try fs.rootDir.createDir(at: "d")

		try fileC.copy(to: "/d")

		try #expect(fs.file(at: "/c").stringContents() == "c content")
		try #expect(fs.file(at: "/d/c").stringContents() == "c content")
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToNothingDuplicates(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let dir = try fs.rootDir.createDir(at: "d")
		try dir.createFile(at: "a").replaceContents("a content")

		try dir.copy(to: "/e")

		try #expect(fs.file(at: "/d/a").stringContents() == "a content")
		try #expect(fs.file(at: "/e/a").stringContents() == "a content")
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a")
		let dir = try fs.rootDir.createDir(at: "d")

		try dir.copy(to: "/a")

		try #expect(fs.rootDir.dir(at: "d") != nil)
		try #expect(fs.rootDir.dir(at: "a") != nil)
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let dir = try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/a").replaceContents("a")
		try fs.createDir(at: "/d/b")
		try fs.createFile(at: "/d/b/c").replaceContents("c")
		try fs.createDir(at: "/e")

		try dir.copy(to: "/e")

		try #expect(fs.file(at: "/d/a").stringContents() == "a")
		try #expect(fs.file(at: "/d/b/c").stringContents() == "c")

		try #expect(fs.file(at: "/e/d/a").stringContents() == "a")
		try #expect(fs.file(at: "/e/d/b/c").stringContents() == "c")
	}

	@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
	func copyPreservesExtendedAttributes(fsKind: FSKind, nodeType: NodeType) throws {
		#if os(Linux)
			// Linux kernel VFS prohibits user-namespaced xattrs on symlinks
			guard nodeType != .symlink else { return }
		#endif

		let fs = self.fs(for: fsKind)
		let (node, _) = try nodeType.createNode(at: "/source", in: fs)

		let originalXattrs = try node.extendedAttributeNames()
		try node.setExtendedAttribute(named: "user.test", to: "value")
		let expectedXattrs = originalXattrs.union(["user.test"])

		try node.copy(to: "/dest")

		let sourceXattrs = try node.extendedAttributeNames()
		#expect(sourceXattrs == expectedXattrs)
		#expect(try node.extendedAttributeString(named: "user.test") == "value")

		let copied = try fs.node(at: "/dest")
		let copiedXattrs = try copied.extendedAttributeNames()
		#expect(copiedXattrs == expectedXattrs)
		#expect(try copied.extendedAttributeString(named: "user.test") == "value")
	}

	@Test(arguments: FSKind.allCases)
	func nodeCopyHandlesRelativePaths(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.rootDir.newOrExistingFile(at: "parent/file.txt")
		try file.replaceContents("content")

		try file.copy(to: "../copied.txt")

		try #expect(fs.file(at: "/parent/file.txt").stringContents() == "content")
		try #expect(fs.file(at: "/copied.txt").stringContents() == "content")
	}
}
