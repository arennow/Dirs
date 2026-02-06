import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func dirContentsEmpty(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		#expect(try fs.contentsOf(directory: "/") == [])
	}

	@Test(arguments: FSKind.allCases)
	func dirContentsNormal(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try fs.createFile(at: "/a")
		try fs.createFile(at: "/b")
		_ = try fs.rootDir.newOrExistingFile(at: "d/d1")

		try #expect(Set(fs.contentsOf(directory: "/")) == [
			.init(filePath: "/a", nodeType: .file),
			.init(filePath: "/b", nodeType: .file),
			.init(filePath: "/d", nodeType: .dir),
		])

		try #expect(fs.contentsOf(directory: "/d") == [
			.init(filePath: "/d/d1", nodeType: .file),
		])
	}

	@Test(arguments: FSKind.allCases)
	func dirContentsSymlink(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		_ = try fs.rootDir.newOrExistingFile(at: "d/d1")
		_ = try fs.rootDir.newOrExistingFile(at: "d/d2")
		try fs.createSymlink(at: "/s", to: "/d")

		try #expect(Set(fs.contentsOf(directory: "/")) == [
			.init(filePath: "/d", nodeType: .dir),
			.init(filePath: "/s", nodeType: .symlink),
		])

		try #expect(Set(fs.contentsOf(directory: "/d")) == [
			.init(filePath: "/d/d1", nodeType: .file),
			.init(filePath: "/d/d2", nodeType: .file),
		])

		try #expect(Set(fs.contentsOf(directory: "/s")) == [
			.init(filePath: "/s/d1", nodeType: .file),
			.init(filePath: "/s/d2", nodeType: .file),
		])
	}

	@Test(arguments: FSKind.allCases)
	func newOrExistingFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("abc")
		try fs.rootDir.newOrExistingFile(at: "x/y/existing").replaceContents("xyz")

		let rootDir = try fs.rootDir

		// Direct children
		try #expect(rootDir.newOrExistingFile(at: "a").stringContents() == "abc")
		try #expect(rootDir.newOrExistingFile(at: "b").stringContents() == "")

		// Nested paths
		try #expect(rootDir.newOrExistingFile(at: "x/y/existing").stringContents() == "xyz")
		try #expect(rootDir.newOrExistingFile(at: "x/y/new").stringContents() == "")
		try #expect(rootDir.newOrExistingFile(at: "c/d/e/deep").stringContents() == "")
		#expect(fs.nodeType(at: "/c/d/e") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func newOrExistingDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.rootDir.newOrExistingFile(at: "d/d1")
		_ = try fs.rootDir.newOrExistingFile(at: "x/y/z/file")

		let rootDir = try fs.rootDir

		// Direct children
		try #expect(rootDir.newOrExistingDir(at: "d").children().all.map(\.name) == ["d1"])
		try #expect(rootDir.newOrExistingDir(at: "e").children().all.map(\.name) == [])

		// Nested paths - existing
		try #expect(rootDir.newOrExistingDir(at: "x/y").file(at: "z/file") != nil)
		// Nested paths - new
		let newDir = try rootDir.newOrExistingDir(at: "a/b/c")
		#expect(newDir.path == "/a/b/c")
		#expect(fs.nodeType(at: "/a/b") == .dir)
		#expect(fs.nodeType(at: "/a") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func childrenIncludesAllNodeTypes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Each node type
		let file = try root.createFile(at: "file.txt")
		let dir = try root.createDir(at: "subdir")
		#if !os(Windows)
			let special = try self.createSpecialNode(named: "special", in: fs)
			try root.createSymlink(at: "symlink_to_special", to: special)
		#endif
		try root.createSymlink(at: "symlink", to: file)
		try root.createSymlink(at: "broken", to: "/nonexistent")
		#if FINDER_ALIASES_ENABLED
			try root.createFinderAlias(at: "alias", to: dir)
		#endif

		let children = try root.children()

		// Verify counts
		#expect(children.files.count == 1)
		#expect(children.directories.count == 1)
		#if os(Windows)
			#expect(children.symlinks.count == 2)
			#expect(children.specials.count == 0)
		#else
			#expect(children.symlinks.count == 3)
			#expect(children.specials.count == 1)
		#endif
		#if FINDER_ALIASES_ENABLED
			#expect(children.finderAliases.count == 1)
		#endif

		// Verify specific paths
		#expect(children.files.map(\.name) == ["file.txt"])
		#expect(children.directories.map(\.name) == ["subdir"])
		#if os(Windows)
			#expect(children.symlinks.map(\.name).sorted() == ["broken", "symlink"])
		#else
			#expect(children.specials.map(\.name) == ["special"])
			#expect(children.symlinks.map(\.name).sorted() == ["broken", "symlink", "symlink_to_special"])
		#endif
		#if FINDER_ALIASES_ENABLED
			#expect(children.finderAliases.map(\.name) == ["alias"])
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func resolvedChildrenResolvesSymlinksAndAliases(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		let targetFile = try root.createFile(at: "target_file")
		let targetDir = try root.createDir(at: "target_dir")
		let symToFile = try root.createSymlink(at: "symlink_to_file", to: targetFile)
		#if !os(Windows)
			let special = try self.createSpecialNode(named: "special", in: fs)
		#endif
		try root.createSymlink(at: "symlink2_to_file", to: targetFile)
		try root.createSymlink(at: "symlink_to_dir", to: targetDir)
		try root.createSymlink(at: "symlink_to_symlink_to_file", to: symToFile)
		#if !os(Windows)
			try root.createSymlink(at: "symlink_to_special", to: special)
		#endif
		try root.createSymlink(at: "broken", to: "/nonexistent")
		#if FINDER_ALIASES_ENABLED
			try root.createFinderAlias(at: "alias_to_file", to: targetFile)
			try root.createFinderAlias(at: "alias_to_symlink_to_file", to: symToFile)
		#endif

		let resolved = try root.resolvedChildren()

		#expect(resolved.symlinks.isEmpty)
		#if FINDER_ALIASES_ENABLED
			#expect(resolved.finderAliases.isEmpty)
		#endif

		var expectedFiles: Set<String> = ["target_file", "symlink_to_file", "symlink2_to_file", "symlink_to_symlink_to_file"]
		#if FINDER_ALIASES_ENABLED
			expectedFiles.insert("alias_to_file")
			expectedFiles.insert("alias_to_symlink_to_file")
		#endif

		#expect(Set(resolved.files.map(\.name)) == expectedFiles)
		#expect(Set(resolved.directories.map(\.name)) == ["target_dir", "symlink_to_dir"])
		#if !os(Windows)
			#expect(Set(resolved.specials.map(\.name)) == ["symlink_to_special", "special"])
		#endif
		#expect(resolved.all.contains { $0.name == "broken" } == false)
	}

	@Test(arguments: FSKind.allCases)
	func childrenCountsMatchDirectoryContents(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Create multiple nodes of various types
		try fs.createFile(at: "/f1")
		try fs.createFile(at: "/f2")
		try fs.createFile(at: "/f3")
		try fs.createDir(at: "/d1")
		try fs.createDir(at: "/d2")
		try fs.createSymlink(at: "/s1", to: "/f1")
		try fs.createSymlink(at: "/s2", to: "/d1")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/a1", to: "/f1")
		#endif

		let children = try root.children()
		let contents = try fs.contentsOf(directory: "/")

		#if FINDER_ALIASES_ENABLED
			#expect(children.files.count + children.directories.count + children.symlinks.count + children.finderAliases.count == contents.count)
		#else
			#expect(children.files.count + children.directories.count + children.symlinks.count == contents.count)
		#endif

		// Individual counts should match
		#expect(children.files.count == contents.count(where: { $0.nodeType == .file }))
		#expect(children.directories.count == contents.count(where: { $0.nodeType == .dir }))
		#expect(children.symlinks.count == contents.count(where: { $0.nodeType == .symlink }))
		#if FINDER_ALIASES_ENABLED
			#expect(children.finderAliases.count == contents.count(where: { $0.nodeType == .finderAlias }))
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func childrenAllSequenceIncludesEverything(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		try fs.createFile(at: "/f1")
		try fs.createDir(at: "/d1")
		try fs.createSymlink(at: "/s1", to: "/f1")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/a1", to: "/d1")
		#endif

		let children = try root.children()
		let allNodes = Array(children.all)
		let allNodesFromSequence = Array(children)

		#expect(allNodes.map(\.path) == allNodesFromSequence.map(\.path))

		#if FINDER_ALIASES_ENABLED
			#expect(allNodes.count == 4)
		#else
			#expect(allNodes.count == 3)
		#endif

		#expect(allNodes.contains { ($0 as? File)?.path == "/f1" })
		#expect(allNodes.contains { ($0 as? Dir)?.path == "/d1" })
		#expect(allNodes.contains { ($0 as? Symlink)?.path == "/s1" })
		#if FINDER_ALIASES_ENABLED
			#expect(allNodes.contains { ($0 as? FinderAlias)?.path == "/a1" })
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func childrenIsEmptyWorks(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let emptyDir = try fs.createDir(at: "/empty")
		#expect(try emptyDir.children().isEmpty)

		let nonEmptyDir = try fs.createDir(at: "/nonempty")
		try fs.createFile(at: "/nonempty/file")
		#expect(try !nonEmptyDir.children().isEmpty)
	}

	@Test(arguments: FSKind.allCases)
	func childrenCountWorks(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let emptyDir = try fs.createDir(at: "/empty")
		#expect(try emptyDir.children().count == 0)

		let dir = try fs.createDir(at: "/dir")
		try fs.createFile(at: "/dir/file1")
		try fs.createFile(at: "/dir/file2")
		try fs.createDir(at: "/dir/subdir")
		try fs.createSymlink(at: "/dir/link", to: "/dir/file1")

		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/dir/alias", to: "/dir/subdir")
			#expect(try dir.children().count == 5) // 2 files, 1 dir, 1 symlink, 1 alias
		#else
			#expect(try dir.children().count == 4) // 2 files, 1 dir, 1 symlink
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func nodeAccessorFunctions(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Direct children
		try fs.createFile(at: "/myfile")
		try fs.createDir(at: "/mydir")
		try fs.createSymlink(at: "/mylink", to: "/myfile")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/myalias", to: "/mydir")
		#endif

		#expect(root.file(at: "myfile")?.path == "/myfile")
		#expect(root.dir(at: "mydir")?.path == "/mydir")
		#expect(root.symlink(at: "mylink")?.path == "/mylink")
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "myalias")?.path == "/myalias")
		#endif

		// Nested paths
		_ = try root.newOrExistingFile(at: "a/b/file")
		try fs.createDir(at: "/a/b/dir")
		try fs.createSymlink(at: "/a/b/link", to: "/a/b/file")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/a/b/alias", to: "/a/b/dir")
		#endif

		#expect(root.file(at: "a/b/file")?.path == "/a/b/file")
		#expect(root.dir(at: "a/b/dir")?.path == "/a/b/dir")
		#expect(root.symlink(at: "a/b/link")?.path == "/a/b/link")
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "a/b/alias")?.path == "/a/b/alias")
		#endif

		// Test non-existent returns nil
		#expect(root.file(at: "nonexistent") == nil)
		#expect(root.dir(at: "nonexistent") == nil)
		#expect(root.symlink(at: "nonexistent") == nil)
		#expect(root.file(at: "a/b/nonexistent") == nil)
		#expect(root.dir(at: "a/b/nonexistent") == nil)
		#expect(root.symlink(at: "a/b/nonexistent") == nil)
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "nonexistent") == nil)
			#expect(root.finderAlias(at: "a/b/nonexistent") == nil)
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func nodeGenericAccessor(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Direct children
		try fs.createFile(at: "/myfile")
		try fs.createDir(at: "/mydir")
		try fs.createSymlink(at: "/mylink", to: "/myfile")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/myalias", to: "/mydir")
		#endif

		#expect(root.node(at: "myfile")?.path == "/myfile")
		#expect(root.node(at: "myfile") is File)
		#expect(root.node(at: "mydir") is Dir)
		#expect(root.node(at: "mylink") is Symlink)
		#if FINDER_ALIASES_ENABLED
			#expect(root.node(at: "myalias") is FinderAlias)
		#endif

		// Nested paths
		_ = try root.newOrExistingFile(at: "a/b/file")
		try fs.createDir(at: "/a/b/dir")
		try fs.createSymlink(at: "/a/b/link", to: "/a/b/file")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/a/b/alias", to: "/a/b/dir")
		#endif

		#expect(root.node(at: "a/b/file") is File)
		#expect(root.node(at: "a/b/dir") is Dir)
		#expect(root.node(at: "a/b/link") is Symlink)
		#if FINDER_ALIASES_ENABLED
			#expect(root.node(at: "a/b/alias") is FinderAlias)
		#endif

		#expect(root.node(at: "nonexistent") == nil)
		#expect(root.node(at: "a/b/nonexistent") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func nodeAccessorsFunctionValidateIntermediatePaths(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		_ = try root.newOrExistingFile(at: "real/nested/file")
		try fs.createFile(at: "/file_not_dir")
		#if FINDER_ALIASES_ENABLED
			try fs.createFinderAlias(at: "/real/nested/alias", to: "/real/nested/file")
		#endif

		#expect(root.file(at: "nonexistent/nested/file") == nil)
		#expect(root.dir(at: "nonexistent/nested/dir") == nil)
		#expect(root.symlink(at: "nonexistent/nested/link") == nil)
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "nonexistent/nested/alias") == nil)
		#endif

		#expect(root.file(at: "file_not_dir/nested/file") == nil)
		#expect(root.dir(at: "file_not_dir/nested/dir") == nil)
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "file_not_dir/nested/alias") == nil)
		#endif

		#expect(root.file(at: "real/nested/nonexistent") == nil)
		#expect(root.dir(at: "real/nested/nonexistent") == nil)
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "real/nested/nonexistent") == nil)
		#endif

		#expect(root.file(at: "file_not_dir/anything") == nil)

		#expect(root.file(at: "real/nested/file")?.path == "/real/nested/file")
		#if FINDER_ALIASES_ENABLED
			#expect(root.finderAlias(at: "real/nested/alias")?.path == "/real/nested/alias")
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func nodeAccessorFunctionsResolveDeeplyNestedSymlinks(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		// Create a 10-layer deep structure with real directories
		// Path: /r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/
		_ = try root.newOrExistingFile(at: "r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/file")
		try fs.createDir(at: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/dir")
		try fs.createSymlink(at: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/link_to_file", to: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/file")
		try fs.createSymlink(at: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/link_to_dir", to: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/dir")

		// Create alternating symlinks for even-numbered levels (0, 2, 4, 6, 8)
		// s0 -> r0, r0/r1/s2 -> r0/r1/r2, r0/r1/r2/r3/s4 -> r0/r1/r2/r3/r4, etc.
		try fs.createSymlink(at: "/s0", to: "/r0")
		try fs.createSymlink(at: "/r0/r1/s2", to: "/r0/r1/r2")
		try fs.createSymlink(at: "/r0/r1/r2/r3/s4", to: "/r0/r1/r2/r3/r4")
		try fs.createSymlink(at: "/r0/r1/r2/r3/r4/r5/s6", to: "/r0/r1/r2/r3/r4/r5/r6")
		try fs.createSymlink(at: "/r0/r1/r2/r3/r4/r5/r6/r7/s8", to: "/r0/r1/r2/r3/r4/r5/r6/r7/r8")

		// Test 1: Access file through deeply nested path with alternating symlinks
		// Path requested: /s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/file
		// Should resolve to: /r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/file
		// But returned path should be the requested one (with symlinks preserved)
		let deepFile = root.file(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/file")
		#expect(deepFile?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/file")

		// Test 2: Access directory through deeply nested path with alternating symlinks
		let deepDir = root.dir(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir")
		#expect(deepDir?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir")

		// Test 3: Access symlink through deeply nested path with alternating symlinks
		let deepSymlink = root.symlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(deepSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// Test 4: Final component is a symlink to a file
		// We can get a file through a symlink path, and it returns the symlink path
		let fileViaSymlink = root.file(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(fileViaSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// We can also still get it as a symlink using descendantSymlink
		let symlinkToFile = root.symlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(symlinkToFile?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// Test 5: Final component is a symlink to a directory
		// Similarly, descendantDir follows symlinks
		let dirViaSymlink = root.dir(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")
		#expect(dirViaSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")

		// We can also get it as a symlink
		let symlinkToDir = root.symlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")
		#expect(symlinkToDir?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")

		// Test 6: We can traverse through symlinks in the path and continue into subdirectories
		try fs.createFile(at: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/dir/nested_file")

		// This works because 's0', 's2', etc. are intermediate components that resolve to dirs
		let nestedFileThroughPath = root.file(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir/nested_file")
		#expect(nestedFileThroughPath?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir/nested_file")
	}
}
