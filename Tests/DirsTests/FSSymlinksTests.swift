import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func symlinkRedirectsToFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let a = try fs.createFile(at: "/a")
		try fs.createSymlink(at: "/s", to: "/a")

		try a.replaceContents("abc")
		try #expect(fs.contentsOf(file: "/s") == Data("abc".utf8))
		try #expect(fs.file(at: "/s").stringContents() == "abc")

		try a.replaceContents("xyz")
		try #expect(fs.contentsOf(file: "/s") == Data("xyz".utf8))
		try #expect(fs.file(at: "/s").stringContents() == "xyz")

		#expect(throws: WrongNodeType.self) {
			try fs.dir(at: "/s")
		}
	}

	@Test(arguments: FSKind.allCases)
	func symlinkRedirectsToDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let f = try fs.rootDir.newOrExistingFile(at: "a/b/c/f")
		try f.replaceContents("abc")

		try fs.createSymlink(at: "/s", to: "/a/b")

		try #expect(fs.contentsOf(directory: "/s").compactMap(\.filePath.lastComponent) == ["c"])
		try #expect(fs.dir(at: "/s").children().directories.compactMap(\.path.lastComponent) == ["c"])
		#expect(throws: WrongNodeType.self) {
			try fs.file(at: "/s")
		}
	}

	@Test(arguments: FSKind.allCases)
	func relativeSymlinkToFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let target = try fs.rootDir.newOrExistingFile(at: "dir/target")
		try target.replaceContents("content")
		let symlink = try fs.createSymlink(at: "/dir/link", to: "target")

		try #expect(symlink.destination == "target")
		let link = try fs.file(at: "/dir/link")
		try #expect(link.stringContents() == "content")

		let resolved = try symlink.resolve()
		#expect(resolved.name == "target")
		try #expect(resolved.realpath() == "/dir/target")
	}

	@Test(arguments: FSKind.allCases)
	func relativeSymlinkToDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.rootDir.newOrExistingFile(at: "dir/subdir/file")
		let symlink = try fs.createSymlink(at: "/dir/link", to: "subdir")

		try #expect(symlink.destination == "subdir")
		let linkAsDir = try fs.dir(at: "/dir/link")
		#expect(try linkAsDir.children().files.compactMap(\.path.lastComponent) == ["file"])

		let resolved = try symlink.resolve()
		#expect(resolved.name == "subdir")
		try #expect(resolved.realpath() == "/dir/subdir")
	}

	@Test(arguments: FSKind.allCases)
	func relativeSymlinkWithDotDot(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let target = try fs.rootDir.newOrExistingFile(at: "a/target")
		_ = try fs.rootDir.newOrExistingFile(at: "a/b/c/deep")
		try target.replaceContents("from_a")

		let symlink = try fs.createSymlink(at: "/a/b/c/link", to: "../../target")

		try #expect(symlink.destination == "../../target")
		let link = try fs.file(at: "/a/b/c/link")
		try #expect(link.stringContents() == "from_a")

		let resolved = try symlink.resolve()
		#expect(resolved.name == "target")
		try #expect(resolved.realpath() == "/a/target")
	}

	@Test(arguments: FSKind.allCases)
	func relativeSymlinkChain(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/file")
		try file.replaceContents("final")
		let symlink = try fs.createSymlink(at: "/link1", to: "link2")
		try fs.createSymlink(at: "/link2", to: "file")

		try #expect(symlink.destination == "link2")
		let link1 = try fs.file(at: "/link1")
		try #expect(link1.stringContents() == "final")

		try #expect(symlink.realpath() == "/file")
	}

	@Test(arguments: FSKind.allCases)
	func relativeSymlinkBroken(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/dir")
		let symlink = try fs.createSymlink(at: "/dir/broken", to: "nonexistent")

		try #expect(symlink.destination == "nonexistent")
		#expect(symlink.nodeType == .symlink)

		#expect(throws: NoSuchNode(path: "/dir/nonexistent")) { try symlink.resolve() }
		#expect(throws: NoSuchNode(path: "/dir/nonexistent")) { try symlink.realpath() }
	}

	@Test(arguments: FSKind.allCases)
	func resolvedSymlinkUsesTargetPathAndName(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.createFile(at: "/a")
		let symlink = try fs.createSymlink(at: "/s", to: "/a")

		#expect(try symlink.destination == "/a")
		let resolved = try symlink.resolve()
		#expect(resolved.path == "/a")
		#expect(resolved.name == "a")
	}

	@Test(arguments: FSKind.allCases)
	func nodesInsideSymlinkDirResolveTypes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.rootDir.newOrExistingFile(at: "a/b/c1")
		_ = try fs.rootDir.newOrExistingFile(at: "a/b/c2")
		_ = try fs.rootDir.newOrExistingFile(at: "a/f")
		try fs.createSymlink(at: "/s", to: "/a")
		try fs.createSymlink(at: "/s2", to: "/s")

		#expect(fs.nodeType(at: "/s") == .symlink)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s") == .dir)
		_ = try fs.dir(at: "/s")

		#expect(fs.nodeType(at: "/s/b") == .dir)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s/b") == .dir)
		_ = try fs.dir(at: "/s/b")

		#expect(fs.nodeType(at: "/s/b/c1") == .file)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s/b/c1") == .file)
		_ = try fs.file(at: "/s/b/c1")

		#expect(fs.nodeType(at: "/s/b/c2") == .file)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s/b/c2") == .file)
		_ = try fs.file(at: "/s/b/c2")

		#expect(fs.nodeType(at: "/s/f") == .file)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s/f") == .file)
		_ = try fs.file(at: "/s/f")

		#expect(fs.nodeType(at: "/s2") == .symlink)
		#expect(fs.nodeTypeResolvingResolvables(at: "/s2") == .dir)
		_ = try fs.symlink(at: "/s2")

		#if FINDER_ALIASES_ENABLED
			try fs.createFile(at: "/a/target")
			try fs.createFinderAlias(at: "/a/alias", to: "/a/target")
			#expect(fs.nodeType(at: "/s/alias") == .finderAlias)
			_ = try fs.finderAlias(at: "/s/alias")
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func symlinkTypeResolvesToReferent(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let symlinks = try Self.prepareForSymlinkTests(fs)
		try #expect(symlinks.file.resolve() is File)
		try #expect(symlinks.dir.resolve() is Dir)
		try #expect(symlinks.fileSym.resolve() is Symlink)
		try #expect(symlinks.dirSym.resolve() is Symlink)
		#expect(throws: NoSuchNode.self, performing: { try symlinks.broken.resolve() })
	}

	@Test(arguments: FSKind.allCases)
	func realpathsIdentifyConcretes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let symlinks = try Self.prepareForSymlinkTests(fs)
		try #expect(symlinks.file.realpath() == "/a")
		try #expect(fs.file(at: "/a").realpath() == "/a")
		try #expect(symlinks.dir.realpath() == "/d")
		try #expect(symlinks.dirSym.realpath() == "/d")
		try #expect(fs.dir(at: "/d").realpath() == "/d")
		try #expect(fs.file(at: "/sd/d1").realpath() == "/d/d1")
	}

	@Test(arguments: FSKind.allCases)
	func nodePointsToSameNodeAsOther(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let symlinks = try Self.prepareForSymlinkTests(fs)

		let file = try fs.file(at: "/a")
		#expect(try file.pointsToSameNode(as: symlinks.file))
		#expect(try !file.pointsToSameNode(as: symlinks.dir))

		let dir = try fs.dir(at: "/d")
		#expect(try dir.pointsToSameNode(as: symlinks.dir))
		#expect(try !dir.pointsToSameNode(as: symlinks.file))
	}

	@Test(arguments: FSKind.allCases)
	func nodePathRelativeToDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let symlinks = try Self.prepareForSymlinkTests(fs)

		let parent = try fs.createDir(at: "/parent")
		let child = try parent.createFile(at: "child")
		let deepDir = try parent.createDir(at: "deeply/nested")
		let nested = try deepDir.createFile(at: "file")

		try #expect(child.descendantPath(from: parent) == "child")
		try #expect(nested.descendantPath(from: parent) == "deeply/nested/file")

		try #expect(parent.descendantPath(from: parent) == "")
		try #expect(child.descendantPath(from: child) == "")

		let d = try fs.dir(at: "/d")
		let descFile = try fs.file(at: "/d/e/e1")
		let a = try fs.file(at: "/a")

		try #expect(descFile.descendantPath(from: d) == "e/e1")
		try #expect(descFile.descendantPath(from: symlinks.dir) == "e/e1")
		try #expect(descFile.descendantPath(from: symlinks.dirSym) == "e/e1")

		#expect(throws: NodeNotDescendantError.self, performing: { try a.descendantPath(from: d) })

		let brokenSym = try fs.createSymlink(at: "/broken_desc", to: "/nonexistent")
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try a.descendantPath(from: brokenSym) }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try brokenSym.descendantPath(from: parent) }
	}

	@Test(arguments: FSKind.allCases)
	func createFileThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		#expect(throws: Never.self) { try fs.createFile(at: "/sd/newFile") }
		#expect(fs.nodeType(at: "/d/newFile") == .file)
		#expect(fs.nodeType(at: "/sd/newFile") == .file)
	}

	@Test(arguments: FSKind.allCases)
	func createDirThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		#expect(throws: Never.self) { try fs.createDir(at: "/sd/newDir") }
		#expect(fs.nodeType(at: "/d/newDir") == .dir)
		#expect(fs.nodeType(at: "/sd/newDir") == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func createSymlinkThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		#expect(throws: Never.self) { try fs.createSymlink(at: "/sd/link", to: "/target") }
		#expect(fs.nodeType(at: "/d/link") == .symlink)
		#expect(fs.nodeType(at: "/sd/link") == .symlink)
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		#expect(throws: Never.self) { try fs.replaceContentsOfFile(at: "/sd/d1", to: "abc") }
		try #expect(fs.contentsOf(file: "/d/d1") == Data("abc".utf8))
		try #expect(fs.contentsOf(file: "/sd/d1") == Data("abc".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func appendContentsOfFileThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.replaceContentsOfFile(at: "/d/d1", to: "initial")
		#expect(throws: Never.self) { try fs.appendContentsOfFile(at: "/sd/d1", with: " appended") }
		try #expect(fs.contentsOf(file: "/d/d1") == Data("initial appended".utf8))
		try #expect(fs.contentsOf(file: "/sd/d1") == Data("initial appended".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func deleteNodeThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		#expect(fs.nodeType(at: "/d/d1") == .file)
		#expect(throws: Never.self) { try fs.deleteNode(at: "/sd/d1") }
		#expect(fs.nodeType(at: "/d/d1") == nil)
		#expect(fs.nodeType(at: "/sd/d1") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func operationsThroughBrokenSymlinkInParentPathFail(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createSymlink(at: "/broken", to: "/nonexistent")

		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.createFile(at: "/broken/file") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.createDir(at: "/broken/dir") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.createSymlink(at: "/broken/link", to: "/target") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.contentsOf(directory: "/broken") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.contentsOf(file: "/broken/file") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.sizeOfFile(at: "/broken/file") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.replaceContentsOfFile(at: "/broken/file", to: "abc") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.appendContentsOfFile(at: "/broken/file", with: "abc") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.deleteNode(at: "/broken/file") }
		#expect(fs.nodeType(at: "/broken/file") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func copyNodeThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.replaceContentsOfFile(at: "/d/d1", to: "content")
		let file = try fs.file(at: "/sd/d1")
		#expect(throws: Never.self) { try file.copy(to: "/sd/d1_copy") }
		#expect(fs.nodeType(at: "/d/d1_copy") == .file)
		#expect(fs.nodeType(at: "/sd/d1_copy") == .file)
		try #expect(fs.contentsOf(file: "/d/d1_copy") == Data("content".utf8))
		try #expect(fs.contentsOf(file: "/sd/d1_copy") == Data("content".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func contentsOfDirectoryThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		let contentsViaReal = try fs.contentsOf(directory: "/d/e")
		let contentsViaSymlink = try fs.contentsOf(directory: "/sd/e")
		#expect(Set(contentsViaReal.map(\.filePath.lastComponent)) == ["e1"])
		#expect(Set(contentsViaSymlink.map(\.filePath.lastComponent)) == ["e1"])
	}

	@Test(arguments: FSKind.allCases)
	func destinationOfSymlinkThroughSymlinkedParentDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try Self.prepareForSymlinkTests(fs)

		try fs.createSymlink(at: "/d/link", to: "/target")
		let destViaReal = try fs.destinationOf(symlink: "/d/link")
		let destViaSymlink = try fs.destinationOf(symlink: "/sd/link")
		#expect(destViaReal == "/target")
		#expect(destViaSymlink == "/target")
	}

	// Reading and writing symlinks through the FS interface is an unusual thing to do,
	// but the expected semantics are that it operates on the target of the symlink.
	// This is in contrast to FinderAlias, which is mostly a regular file, and thus
	// reading/writing operates on the alias data itself

	@Test(arguments: FSKind.allCases)
	func contentsOfSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/target")
		try file.replaceContents("target content")
		try fs.createSymlink(at: "/symlink", to: "/target")

		let symlinkContents = try fs.contentsOf(file: "/symlink")

		// Reading through a symlink should transparently return the target's contents
		let asText = String(data: symlinkContents, encoding: .utf8)
		#expect(asText == "target content", "Symlink read should return target content")

		// Verify the symlink itself is still intact
		#expect(fs.nodeType(at: "/symlink") == .symlink)
		let destination = try fs.destinationOf(symlink: "/symlink")
		#expect(destination == "/target")
	}

	@Test(arguments: FSKind.allCases)
	func writeSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/target")
		try file.replaceContents("initial content")
		try fs.createSymlink(at: "/symlink", to: "/target")

		// Writing to symlink path should write through to the target
		try fs.replaceContentsOfFile(at: "/symlink", to: "modified content")

		// The target file should have the new content
		let targetContents = try fs.contentsOf(file: "/target")
		#expect(String(data: targetContents, encoding: .utf8) == "modified content")

		// The symlink should still be a symlink pointing to the same target
		#expect(fs.nodeType(at: "/symlink") == .symlink)
		let destination = try fs.destinationOf(symlink: "/symlink")
		#expect(destination == "/target")
	}

	@Test(arguments: FSKind.allCases)
	func brokenSymlinkBehavior(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let brokenSym = try fs.createSymlink(at: "/s", to: "/nonexistent")

		#expect(fs.nodeType(at: "/s") == .symlink)

		try #expect(fs.destinationOf(symlink: "/s") == "/nonexistent")

		#expect(throws: NodeAlreadyExists(path: "/s", type: .symlink)) { try fs.createFile(at: "/s") }
		#expect(throws: NodeAlreadyExists(path: "/s", type: .symlink)) { try fs.createDir(at: "/s") }

		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.replaceContentsOfFile(at: "/s", to: "abc") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.appendContentsOfFile(at: "/s", with: "abc") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.contentsOf(directory: "/s") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.contentsOf(file: "/s") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try fs.sizeOfFile(at: "/s") }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try brokenSym.realpath() }
		#expect(throws: NoSuchNode(path: "/nonexistent")) { try brokenSym.resolve() }

		#expect(throws: Never.self) { try fs.deleteNode(at: "/s") }
		#expect(fs.nodeType(at: "/s") == nil)

		// Copying a broken symlink should succeed
		let brokenSym2 = try fs.createSymlink(at: "/s2", to: "/alsoNonexistent")
		try brokenSym2.copy(to: "/s2_copy")
		#expect(fs.nodeType(at: "/s2_copy") == .symlink)
		try #expect(fs.destinationOf(symlink: "/s2_copy") == "/alsoNonexistent")

		// Copying over a broken symlink should succeed
		try fs.createFile(at: "/file").replaceContents("content")
		_ = try fs.createSymlink(at: "/broken_dest", to: "/nowhere")
		try fs.file(at: "/file").copy(to: "/broken_dest")
		#expect(fs.nodeType(at: "/broken_dest") == .file)
		try #expect(fs.file(at: "/broken_dest").stringContents() == "content")

		// Realpath on a chain of symlinks that ends in a broken link should fail
		try fs.createSymlink(at: "/chain1", to: "/chain2")
		try fs.createSymlink(at: "/chain2", to: "/chain3")
		try fs.createSymlink(at: "/chain3", to: "/broken_target")
		#expect(fs.nodeType(at: "/chain1") == .symlink)
		#expect(throws: NoSuchNode(path: "/broken_target")) { try fs.file(at: "/chain1") }
		let chain1Sym = try fs.symlink(at: "/chain1")
		#expect(throws: NoSuchNode(path: "/broken_target")) { try chain1Sym.realpath() }

		// Moving a broken symlink should succeed
		var brokenSym3 = try fs.createSymlink(at: "/broken_to_move", to: "/missing")
		try brokenSym3.move(to: "/broken_moved")
		#expect(brokenSym3.path == "/broken_moved")
		#expect(fs.nodeType(at: "/broken_moved") == .symlink)
		try #expect(fs.destinationOf(symlink: "/broken_moved") == "/missing")
		#expect(fs.nodeType(at: "/broken_to_move") == nil)

		// Renaming a broken symlink should succeed
		var brokenSym4 = try fs.createSymlink(at: "/broken_to_rename", to: "/absent")
		try brokenSym4.rename(to: "broken_renamed")
		#expect(brokenSym4.path == "/broken_renamed")
		#expect(fs.nodeType(at: "/broken_renamed") == .symlink)
		try #expect(fs.destinationOf(symlink: "/broken_renamed") == "/absent")

		// pointsToSameNode with broken symlinks should fail
		let workingFile = try fs.createFile(at: "/working")
		#expect(throws: NoSuchNode(path: "/absent")) { try brokenSym4.pointsToSameNode(as: workingFile) }

		// parent property should work on broken symlinks
		let brokenParent = try brokenSym4.parent
		#expect(brokenParent.path == "/")

		// isAncestor should work with broken symlinks when paths match directly
		// but fail when realpath is needed
		let subdir = try fs.createDir(at: "/subdir")
		let fileInSubdir = try subdir.createFile(at: "file")
		let brokenInSubdir = try fs.createSymlink(at: "/subdir/broken", to: "/void")
		// This works because /subdir/broken starts with /subdir (no realpath needed)
		#expect(try subdir.isAncestor(of: brokenInSubdir))
		// This fails because broken symlink's realpath can't be computed
		#expect(throws: NoSuchNode(path: "/void")) { try brokenInSubdir.isAncestor(of: fileInSubdir) }

		#if XATTRS_ENABLED
			// Extended attributes on broken symlinks
			let brokenForXattr = try fs.createSymlink(at: "/broken_xattr", to: "/nowhere")
			#if os(Linux)
				// Linux kernel VFS prohibits user-namespaced xattrs on symlinks
				#expect(throws: XAttrNotAllowed(path: "/broken_xattr")) {
					try brokenForXattr.setExtendedAttribute(named: "user.test", to: "value")
				}
			#else
				// On macOS, extended attributes on broken symlinks should work
				try brokenForXattr.setExtendedAttribute(named: "user.test", to: "value")
				let retrievedValue = try brokenForXattr.extendedAttributeString(named: "user.test")
				#expect(retrievedValue == "value")
				let xattrNames = try brokenForXattr.extendedAttributeNames()
				#expect(xattrNames.contains("user.test"))
			#endif
		#endif
	}

	@discardableResult
	static func prepareForSymlinkTests(_ fs: any FilesystemInterface) throws ->
		(file: Symlink,
		 dir: Symlink,
		 fileSym: Symlink,
		 dirSym: Symlink,
		 broken: Symlink)
	{
		try fs.createFile(at: "/a").replaceContents("abc")
		try fs.createFile(at: "/b").replaceContents("bcd")
		_ = try fs.rootDir.newOrExistingFile(at: "d/d1")
		_ = try fs.rootDir.newOrExistingFile(at: "d/e/e1")

		let fileSym = try fs.createSymlink(at: "/s", to: "/a")
		let dirSym = try fs.createSymlink(at: "/sd", to: "/d")
		let fileSymSym = try fs.createSymlink(at: "/ss", to: "/s")
		let dirSymSym = try fs.createSymlink(at: "/ssd", to: "/sd")
		let brokenSym = try fs.createSymlink(at: "/sb", to: "/x")

		return (fileSym, dirSym, fileSymSym, dirSymSym, brokenSym)
	}

	@Test(arguments: FSKind.allCases)
	func realpathDetectsCircularSymlinkDirect(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createSymlink(at: "/loop", to: "/loop")

		#expect(throws: CircularResolvableChain.self) {
			try fs.realpathOf(node: "/loop")
		}
	}

	@Test(arguments: FSKind.allCases)
	func realpathDetectsCircularSymlinkChain(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createSymlink(at: "/a", to: "/b")
		try fs.createSymlink(at: "/b", to: "/c")
		try fs.createSymlink(at: "/c", to: "/a")

		#expect(throws: CircularResolvableChain.self) {
			try fs.realpathOf(node: "/a")
		}
	}
}
