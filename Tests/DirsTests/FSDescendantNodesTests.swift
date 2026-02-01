import Dirs
import Foundation
import SortAndFilter
import SystemPackage
import Testing

extension FSTests {
	private static func prepareForRecursiveNodesTests(_ fs: any FilesystemInterface) throws {
		let root = try fs.rootDir
		_ = try root.newOrExistingFile(at: "a1/a1f")
		_ = try root.newOrExistingFile(at: "a1/a2f")
		_ = try root.newOrExistingFile(at: "a1/a2/a1a2f")
		_ = try root.newOrExistingFile(at: "a1/a2/a3/a1a2a3f")
		_ = try root.newOrExistingFile(at: "b1/b2/b3/b1b2b3f")
	}

	@Test(arguments: FSKind.allCases)
	func descendantNodeSequenceYieldsAll(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForRecursiveNodesTests(fs)

		let names = Set(try fs.rootDir.allDescendantNodes().map(\.name))
		#expect(names == [
			"a1", "a2", "a3", "b1", "b2", "b3",
			"a1f", "a2f", "a1a2f", "a1a2a3f", "b1b2b3f",
		])
	}

	@Test(arguments: FSKind.allCases)
	func descendantDirSequenceYieldsAll(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForRecursiveNodesTests(fs)

		let names = Set(try fs.rootDir.allDescendantDirs().map(\.name))
		#expect(names == ["a1", "a2", "a3", "b1", "b2", "b3"])
	}

	@Test(arguments: FSKind.allCases)
	func descendantFileSequenceYieldsAll(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForRecursiveNodesTests(fs)

		let names = Set(try fs.rootDir.allDescendantFiles().map(\.name))
		#expect(names == ["a1f", "a2f", "a1a2f", "a1a2a3f", "b1b2b3f"])
	}

	@Test(arguments: FSKind.allCases)
	func descendantSequencesIncludeSymlinksAndAliases(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Create a hierarchy with all node types
		_ = try root.newOrExistingFile(at: "a/file")
		try fs.createDir(at: "/a/dir")
		try fs.createSymlink(at: "/a/link", to: "/a/file")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/a/alias", to: "/a/dir")
		#endif

		// Test individual descendant sequences
		let files = Array(root.allDescendantFiles())
		let dirs = Array(root.allDescendantDirs())
		let symlinks = Array(root.allDescendantSymlinks())

		#expect(Set(files.map(\.path)) == ["/a/file"])
		#expect(Set(dirs.map(\.path)) == ["/a", "/a/dir"])
		#expect(Set(symlinks.map(\.path)) == ["/a/link"])

		#if canImport(Darwin)
			let aliases = Array(root.allDescendantFinderAliases())
			#expect(Set(aliases.map(\.path)) == ["/a/alias"])
		#endif

		// Test that allDescendantNodes includes everything
		let allNodes = Array(root.allDescendantNodes())
		#if canImport(Darwin)
			#expect(allNodes.count == 5) // dir /a, file, dir, link, alias
		#else
			#expect(allNodes.count == 4) // dir /a, file, dir, link
		#endif
	}
}
