import Dirs
import Foundation
import SortAndFilter
import SystemPackage
import Testing

final class DirsTests {
	var pathToDelete: FilePath?

	deinit {
		guard let pathToDelete = self.pathToDelete else { return }
		try? FileManager.default.removeItem(at: pathToDelete.url)
	}

	enum FSKind: CaseIterable {
		case mock

		#if canImport(Darwin)
			// All of this silliness is required because realFS will always be able to get
			// Finder Info because we're running on APFS, so we need to be able to simulate
			// its absence (as would be the case on a non-Mac filesystem)
			enum FinderInfoAvailability: CaseIterable, CustomDebugStringConvertible {
				case available, unavailable

				var debugDescription: String {
					switch self {
						case .available: return "withFinderInfo"
						case .unavailable: return "withoutFinderInfo"
					}
				}
			}

			case real(FinderInfoAvailability)

			static var allCases: [FSKind] {
				var cases: [FSKind] = [.mock]
				for availability in FinderInfoAvailability.allCases {
					cases.append(.real(availability))
				}
				return cases
			}
		#else
			case real
		#endif
	}

	private func fs(for kind: FSKind) -> any FilesystemInterface {
		switch kind {
			case .mock:
				return MockFSInterface()
			case .real:
				assert(self.pathToDelete == nil, "Each RealFSInterface test requires a unique chroot")
				var fs = try! RealFSInterface(chroot: .temporaryUnique())

				#if canImport(Darwin)
					if case .real(.unavailable) = kind {
						fs.forceMissingFinderInfo = true
					}
				#endif

				self.pathToDelete = fs.chroot
				return fs
		}
	}

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
		// Make sure we don't just support literals ⬇️
		#expect(d.childFile(named: "a1" as String) != nil)
		#expect(d.childFile(named: "a2") == nil)
		#expect(d.childFile(named: "a3") == nil)
		#expect(d.childFile(named: "a4") == nil)

		#expect(d.childDir(named: "a1") == nil)
		// Make sure we don't just support literals ⬇️
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
	func nodeIsEqual(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file1 = try fs.createFile(at: "/file1")
		let file2 = try fs.createFile(at: "/file2")
		let dir = try fs.createDir(at: "/dir")

		let file1AsNode: any Node = file1
		let file2AsNode: any Node = file2
		let dirAsNode: any Node = dir

		#expect(file1.isEqual(to: file1AsNode))
		#expect(!file1.isEqual(to: file2AsNode))
		#expect(!file1.isEqual(to: dirAsNode))
		#expect(dir.isEqual(to: dirAsNode))
	}

	@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
	func createAllNodeKinds(fsKind: FSKind, nodeType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		let (newNode, optionalTarget) = try nodeType.createNode(at: "/newNode", in: fs)
		#expect(newNode.path == "/newNode")
		#expect(newNode.nodeType == nodeType)
		if nodeType.isResolvable {
			let target = try #require(optionalTarget)
			#expect(target.path == "/target")
		}
	}

	@Test(arguments: {
		var combinations: Array<(FSKind, NodeType, NodeType)> = []
		for fsKind in FSKind.allCases {
			for firstType in NodeType.allCreatableCases {
				for secondType in NodeType.allCreatableCases {
					combinations.append((fsKind, firstType, secondType))
				}
			}
		}
		return combinations
	}())
	func creatingNodeOverExistingNodeFails(fsKind: FSKind, firstType: NodeType, secondType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		let testPath: FilePath = "/test"

		_ = try firstType.createNode(at: testPath, in: fs)
		#expect(fs.nodeType(at: testPath) == firstType)

		// Try to create the second node at the same path
		#expect {
			_ = try secondType.createNode(at: testPath, in: fs)
		} throws: { error in
			guard let nodeExists = error as? NodeAlreadyExists else {
				Issue.record("Expected NodeAlreadyExists, got \(type(of: error)): \(error)")
				return false
			}
			return nodeExists.path == testPath && nodeExists.type == firstType
		}

		#expect(fs.nodeType(at: testPath) == firstType)
	}

	@Test(arguments: FSKind.allCases, NodeType.allCreatableCases)
	func hashBehavior(fsKind: FSKind, nodeType: NodeType) throws {
		let fs = self.fs(for: fsKind)

		var (node, _) = try nodeType.createNode(at: "/old", in: fs)

		// Equal nodes have same hash
		let node1 = try fs.node(at: "/old")
		let node2 = try fs.node(at: "/old")
		#expect(node1.isEqual(to: node2))
		#expect(node1.hashValue == node2.hashValue)

		// Hash is consistent within execution
		#expect(node.hashValue == node.hashValue)

		// Hash updates after rename
		let oldHash = node.hashValue
		try node.rename(to: "new")
		let newHash = node.hashValue
		#expect(oldHash != newHash)
	}

	// MARK: - Create File

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

	// MARK: - Mutate File

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
	func brokenSymlinkBehavior(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let brokenSym = try fs.createSymlink(at: "/s", to: "/nonexistent")

		#expect(fs.nodeType(at: "/s") == .symlink)

		try #expect(fs.destinationOf(symlink: "/s") == "/nonexistent")

		#expect(throws: (any Error).self) { try fs.replaceContentsOfFile(at: "/s", to: "abc") }

		#expect(throws: (any Error).self) { try fs.appendContentsOfFile(at: "/s", with: "abc") }

		#expect(throws: (any Error).self) { try fs.createFile(at: "/s") }

		#expect(throws: (any Error).self) { try fs.createDir(at: "/s") }

		#expect(throws: (any Error).self) { try fs.contentsOf(directory: "/s") }

		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/s") }

		#expect(throws: (any Error).self) { try fs.sizeOfFile(at: "/s") }

		#expect(throws: (any Error).self) { try brokenSym.realpath() }

		#expect(throws: NoSuchNode.self) { try brokenSym.resolve() }

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
		#expect(throws: (any Error).self) { try fs.file(at: "/chain1") }
		let chain1Sym = try fs.symlink(at: "/chain1")
		#expect(throws: (any Error).self) { try chain1Sym.realpath() }

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
		#expect(throws: (any Error).self) { try brokenSym4.pointsToSameNode(as: workingFile) }

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
		#expect(throws: (any Error).self) { try brokenInSubdir.isAncestor(of: fileInSubdir) }

		#if canImport(Darwin) || os(Linux)
			// Extended attributes on broken symlinks
			let brokenForXattr = try fs.createSymlink(at: "/broken_xattr", to: "/nowhere")
			#if os(Linux)
				// Linux kernel VFS prohibits user-namespaced xattrs on symlinks
				#expect(throws: (any Error).self) {
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

	// MARK: - File Size

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

	// MARK: - Delete File

	@Test(arguments: FSKind.allCases)
	func deleteNode(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a")
		try fs.createFile(at: "/b")
		try fs.createFile(at: "/c").replaceContents("c content")
		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/E").replaceContents("enough!")
		try fs.createDir(at: "/f")

		try fs.deleteNode(at: "/a")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/a") }

		try fs.deleteNode(at: "/d")
		#expect(throws: (any Error).self) { try fs.contentsOf(file: "/d/E") }
	}

	@Test(arguments: FSKind.allCases)
	func deleteNonexistentNodeFails(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)
		#expect(throws: (any Error).self) { try fs.deleteNode(at: "/a") }
	}

	@Test(arguments: FSKind.allCases)
	func fileParent(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let a = try fs.createFile(at: "/a")

		#expect(try a.parent == fs.rootDir)
		#expect(try a.parent.parent == fs.rootDir)
	}

	// MARK: - Miscellaneous

	@Test(arguments: FSKind.allCases)
	func dirInitNonExisting(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
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

	@Test(arguments: FSKind.allCases, ResolvableNodeType.allCases)
	func resolvableKindCreateAndResolve(fsKind: FSKind, rType: ResolvableNodeType) throws {
		let fs = self.fs(for: fsKind)
		try fs.createFile(at: "/target")

		let rNode = try rType.createResolvableNode(at: "/resolvable", to: "/target", in: fs)
		#expect(rNode.path == "/resolvable")
		#expect(rNode.resolvableNodeType == rType)

		let resolved = try rNode.resolve()
		#expect(resolved.path == "/target")
	}
}

// MARK: - Moves

extension DirsTests {
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

		try #expect(fs.rootDir.childDir(named: "d") == nil)
		try #expect(fs.rootDir.childDir(named: "a") != nil)
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

	@discardableResult
	private static func prepareForSymlinkTests(_ fs: any FilesystemInterface) throws ->
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
}

// MARK: - Copies

extension DirsTests {
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

		try #expect(fs.rootDir.childDir(named: "d") != nil)
		try #expect(fs.rootDir.childDir(named: "a") != nil)
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
}

// MARK: - Renames

extension DirsTests {
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

// MARK: - Node At

extension DirsTests {
	@Test(arguments: FSKind.allCases)
	func nodeAtFunctionReturnsDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let dir = try fs.createDir(at: "/mydir")

		let node = try fs.node(at: "/mydir")
		#expect(node is Dir)
		guard let retrievedDir = node as? Dir else {
			Issue.record("Expected Dir, got \(type(of: node))")
			return
		}
		#expect(retrievedDir.path == dir.path)
	}

	@Test(arguments: FSKind.allCases)
	func nodeAtFunctionReturnsFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/myfile")

		let node = try fs.node(at: "/myfile")
		#expect(node is File)
		guard let retrievedFile = node as? File else {
			Issue.record("Expected File, got \(type(of: node))")
			return
		}
		#expect(retrievedFile.path == file.path)
	}

	@Test(arguments: FSKind.allCases)
	func nodeAtFunctionReturnsSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try fs.createFile(at: "/target")
		let symlink = try fs.createSymlink(at: "/link", to: "/target")

		let node = try fs.node(at: "/link")
		#expect(node is Symlink)
		guard let retrievedSymlink = node as? Symlink else {
			Issue.record("Expected Symlink, got \(type(of: node))")
			return
		}
		#expect(retrievedSymlink.path == symlink.path)
	}

	@Test(arguments: FSKind.allCases)
	func nodeAtFunctionThrowsForNonexistent(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) { try fs.node(at: "/nonexistent") }
	}
}

// MARK: - Dir Lookup

extension DirsTests {
	@Test(arguments: FSKind.allCases, [DirLookupKind.documents, .cache])
	func dirLookupNonTemporary(_ fsKind: FSKind, dlk: DirLookupKind) throws {
		let fs = self.fs(for: fsKind)

		let one = try fs.lookUpDir(dlk)
		let two = try fs.lookUpDir(dlk)

		#expect(one.path.string.localizedCaseInsensitiveContains(dlk.rawValue))
		#expect(one == two)
	}

	@Test(arguments: FSKind.allCases, [DirLookupKind.home, .downloads])
	func dirLookupHomeAndDownloads(_ fsKind: FSKind, dlk: DirLookupKind) throws {
		let fs = self.fs(for: fsKind)

		let one = try fs.lookUpDir(dlk)
		let two = try fs.lookUpDir(dlk)

		#expect(one == two)
	}

	@Test(arguments: FSKind.allCases)
	func dirLookupUniqueTemporary(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let one = try fs.lookUpDir(.uniqueTemporary)
		let two = try fs.lookUpDir(.uniqueTemporary)

		#expect(one != two)
		#expect(one.path.string.localizedCaseInsensitiveContains("temporary"))
		#expect(two.path.string.localizedCaseInsensitiveContains("temporary"))
	}

	@Test(arguments: FSKind.allCases)
	func dirLookupUniqueTemporaryDescendsTemporary(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let unique = try fs.lookUpDir(.uniqueTemporary)
		let temp = try fs.lookUpDir(.temporary)

		try #expect(unique.parent == temp)
	}
}

// MARK: - Directory Contents

extension DirsTests {
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
	func childNodes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFile(at: "/a").replaceContents("abc")
		_ = try fs.rootDir.newOrExistingFile(at: "d/d1")

		let rootDir = try fs.rootDir

		try #expect(rootDir.childFile(named: "a")?.stringContents() == "abc")
		#expect(rootDir.childDir(named: "d")?.childFile(named: "d1") != nil)
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
		try #expect(rootDir.newOrExistingDir(at: "x/y").descendantFile(at: "z/file") != nil)
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

		// Create one of each node type
		try fs.createFile(at: "/file1.txt")
		try fs.createDir(at: "/subdir")
		try fs.createSymlink(at: "/symlink1", to: "/file1.txt")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/alias1", to: "/subdir")
		#endif

		let children = try root.children()

		// Verify all node types are included
		#expect(children.files.count == 1)
		#expect(children.directories.count == 1)
		#expect(children.symlinks.count == 1)
		#if canImport(Darwin)
			#expect(children.finderAliases.count == 1)
		#endif

		// Verify specific paths
		#expect(children.files.first?.path == "/file1.txt")
		#expect(children.directories.first?.path == "/subdir")
		#expect(children.symlinks.first?.path == "/symlink1")
		#if canImport(Darwin)
			#expect(children.finderAliases.first?.path == "/alias1")
		#endif
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
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/a1", to: "/f1")
		#endif

		let children = try root.children()
		let contents = try fs.contentsOf(directory: "/")

		#if canImport(Darwin)
			// Total should match
			#expect(children.files.count + children.directories.count + children.symlinks.count + children.finderAliases.count == contents.count)
		#else
			#expect(children.files.count + children.directories.count + children.symlinks.count == contents.count)
		#endif

		// Individual counts should match
		#expect(children.files.count == contents.count(where: { $0.nodeType == .file }))
		#expect(children.directories.count == contents.count(where: { $0.nodeType == .dir }))
		#expect(children.symlinks.count == contents.count(where: { $0.nodeType == .symlink }))
		#if canImport(Darwin)
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
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/a1", to: "/d1")
		#endif

		let children = try root.children()
		let allNodes = Array(children.all)
		let allNodesFromSequence = Array(children)

		#expect(allNodes.map(\.path) == allNodesFromSequence.map(\.path))

		#if canImport(Darwin)
			#expect(allNodes.count == 4)
		#else
			#expect(allNodes.count == 3)
		#endif

		#expect(allNodes.contains { ($0 as? File)?.path == "/f1" })
		#expect(allNodes.contains { ($0 as? Dir)?.path == "/d1" })
		#expect(allNodes.contains { ($0 as? Symlink)?.path == "/s1" })
		#if canImport(Darwin)
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

		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/dir/alias", to: "/dir/subdir")
			#expect(try dir.children().count == 5) // 2 files, 1 dir, 1 symlink, 1 alias
		#else
			#expect(try dir.children().count == 4) // 2 files, 1 dir, 1 symlink
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func childNodeAccessorFunctions(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		try fs.createFile(at: "/myfile")
		try fs.createDir(at: "/mydir")
		try fs.createSymlink(at: "/mylink", to: "/myfile")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/myalias", to: "/mydir")
		#endif

		// Test by component
		#expect(root.childFile(named: FilePath.Component("myfile"))?.path == "/myfile")
		#expect(root.childDir(named: FilePath.Component("mydir"))?.path == "/mydir")
		#expect(root.childSymlink(named: FilePath.Component("mylink"))?.path == "/mylink")
		#if canImport(Darwin)
			#expect(root.childFinderAlias(named: FilePath.Component("myalias"))?.path == "/myalias")
		#endif

		// Test by string
		#expect(root.childFile(named: "myfile")?.path == "/myfile")
		#expect(root.childDir(named: "mydir")?.path == "/mydir")
		#expect(root.childSymlink(named: "mylink")?.path == "/mylink")
		#if canImport(Darwin)
			#expect(root.childFinderAlias(named: "myalias")?.path == "/myalias")
		#endif

		// Test non-existent returns nil
		#expect(root.childFile(named: "nonexistent") == nil)
		#expect(root.childSymlink(named: "nonexistent") == nil)
		#if canImport(Darwin)
			#expect(root.childFinderAlias(named: "nonexistent") == nil)
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func childNodeGenericAccessor(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		try fs.createFile(at: "/myfile")
		try fs.createDir(at: "/mydir")
		try fs.createSymlink(at: "/mylink", to: "/myfile")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/myalias", to: "/mydir")
		#endif

		#expect(root.child(named: FilePath.Component("myfile"))?.path == "/myfile")
		#expect(root.child(named: "myfile")?.path == "/myfile")
		#expect(root.child(named: "myfile") is File)
		#expect(root.child(named: "mydir") is Dir)
		#expect(root.child(named: "mylink") is Symlink)
		#if canImport(Darwin)
			#expect(root.child(named: "myalias") is FinderAlias)
		#endif
		#expect(root.child(named: "nonexistent") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func descendantNodeAccessorFunctions(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		_ = try root.newOrExistingFile(at: "a/b/file")
		try fs.createDir(at: "/a/b/dir")
		try fs.createSymlink(at: "/a/b/link", to: "/a/b/file")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/a/b/alias", to: "/a/b/dir")
		#endif

		#expect(root.descendantFile(at: "a/b/file")?.path == "/a/b/file")
		#expect(root.descendantDir(at: "a/b/dir")?.path == "/a/b/dir")
		#expect(root.descendantSymlink(at: "a/b/link")?.path == "/a/b/link")
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "a/b/alias")?.path == "/a/b/alias")
		#endif

		// Test non-existent returns nil
		#expect(root.descendantFile(at: "a/b/nonexistent") == nil)
		#expect(root.descendantSymlink(at: "a/b/nonexistent") == nil)
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "a/b/nonexistent") == nil)
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func descendantNodeGenericAccessor(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		_ = try root.newOrExistingFile(at: "a/b/file")
		try fs.createDir(at: "/a/b/dir")
		try fs.createSymlink(at: "/a/b/link", to: "/a/b/file")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/a/b/alias", to: "/a/b/dir")
		#endif

		// Test with FilePath
		#expect(root.descendant(at: FilePath("a/b/file")) is File)
		#expect(root.descendant(at: FilePath("a/b/dir")) is Dir)
		#expect(root.descendant(at: FilePath("a/b/link")) is Symlink)
		#if canImport(Darwin)
			#expect(root.descendant(at: FilePath("a/b/alias")) is FinderAlias)
		#endif

		// Test with String
		#expect(root.descendant(at: "a/b/file") is File)
		#expect(root.descendant(at: "a/b/dir") is Dir)
		#expect(root.descendant(at: "a/b/link") is Symlink)
		#if canImport(Darwin)
			#expect(root.descendant(at: "a/b/alias") is FinderAlias)
		#endif

		#expect(root.descendant(at: "a/b/nonexistent") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func descendantNodeAccessorsFunctionValidateIntermediatePaths(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir

		_ = try root.newOrExistingFile(at: "real/nested/file")
		try fs.createFile(at: "/file_not_dir")
		#if canImport(Darwin)
			try fs.createFinderAlias(at: "/real/nested/alias", to: "/real/nested/file")
		#endif

		#expect(root.descendantFile(at: "nonexistent/nested/file") == nil)
		#expect(root.descendantDir(at: "nonexistent/nested/dir") == nil)
		#expect(root.descendantSymlink(at: "nonexistent/nested/link") == nil)
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "nonexistent/nested/alias") == nil)
		#endif

		#expect(root.descendantFile(at: "file_not_dir/nested/file") == nil)
		#expect(root.descendantDir(at: "file_not_dir/nested/dir") == nil)
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "file_not_dir/nested/alias") == nil)
		#endif

		#expect(root.descendantFile(at: "real/nested/nonexistent") == nil)
		#expect(root.descendantDir(at: "real/nested/nonexistent") == nil)
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "real/nested/nonexistent") == nil)
		#endif

		#expect(root.descendantFile(at: "file_not_dir/anything") == nil)

		#expect(root.descendantFile(at: "real/nested/file")?.path == "/real/nested/file")
		#if canImport(Darwin)
			#expect(root.descendantFinderAlias(at: "real/nested/alias")?.path == "/real/nested/alias")
		#endif
	}

	@Test(arguments: FSKind.allCases)
	func descendantNodeAccessorFunctionsResolveDeeplyNestedSymlinks(fsKind: FSKind) throws {
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
		let deepFile = root.descendantFile(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/file")
		#expect(deepFile?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/file")

		// Test 2: Access directory through deeply nested path with alternating symlinks
		let deepDir = root.descendantDir(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir")
		#expect(deepDir?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir")

		// Test 3: Access symlink through deeply nested path with alternating symlinks
		let deepSymlink = root.descendantSymlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(deepSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// Test 4: Final component is a symlink to a file
		// We can get a file through a symlink path, and it returns the symlink path
		let fileViaSymlink = root.descendantFile(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(fileViaSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// We can also still get it as a symlink using descendantSymlink
		let symlinkToFile = root.descendantSymlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")
		#expect(symlinkToFile?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_file")

		// Test 5: Final component is a symlink to a directory
		// Similarly, descendantDir follows symlinks
		let dirViaSymlink = root.descendantDir(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")
		#expect(dirViaSymlink?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")

		// We can also get it as a symlink
		let symlinkToDir = root.descendantSymlink(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")
		#expect(symlinkToDir?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/link_to_dir")

		// Test 6: We can traverse through symlinks in the path and continue into subdirectories
		try fs.createFile(at: "/r0/r1/r2/r3/r4/r5/r6/r7/r8/r9/dir/nested_file")

		// This works because 's0', 's2', etc. are intermediate components that resolve to dirs
		let nestedFileThroughPath = root.descendantFile(at: "s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir/nested_file")
		#expect(nestedFileThroughPath?.path == "/s0/r1/s2/r3/s4/r5/s6/r7/s8/r9/dir/nested_file")
	}
}

// MARK: - Descendant Nodes

extension DirsTests {
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

// MARK: - Symlinks

extension DirsTests {
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
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s") == .dir)
		_ = try fs.dir(at: "/s")

		#expect(fs.nodeType(at: "/s/b") == .dir)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s/b") == .dir)
		_ = try fs.dir(at: "/s/b")

		#expect(fs.nodeType(at: "/s/b/c1") == .file)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s/b/c1") == .file)
		_ = try fs.file(at: "/s/b/c1")

		#expect(fs.nodeType(at: "/s/b/c2") == .file)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s/b/c2") == .file)
		_ = try fs.file(at: "/s/b/c2")

		#expect(fs.nodeType(at: "/s/f") == .file)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s/f") == .file)
		_ = try fs.file(at: "/s/f")

		#expect(fs.nodeType(at: "/s2") == .symlink)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/s2") == .dir)
		_ = try fs.symlink(at: "/s2")

		#if canImport(Darwin)
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
		#expect(throws: (any Error).self) { try a.descendantPath(from: brokenSym) }
		#expect(throws: (any Error).self) { try brokenSym.descendantPath(from: parent) }
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

		#expect(throws: (any Error).self) { try fs.createFile(at: "/broken/file") }
		#expect(throws: (any Error).self) { try fs.createDir(at: "/broken/dir") }
		#expect(throws: (any Error).self) { try fs.createSymlink(at: "/broken/link", to: "/target") }
		#expect(throws: (any Error).self) { try fs.contentsOf(directory: "/broken") }
		#expect(throws: (any Error).self) { try fs.replaceContentsOfFile(at: "/broken/file", to: "abc") }
		#expect(throws: (any Error).self) { try fs.deleteNode(at: "/broken/file") }
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
}

// MARK: - Finder Aliases

#if canImport(Darwin)
	extension DirsTests {
		@Test(arguments: FSKind.allCases)
		func finderAliasRoundTrip(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			let resolved = try alias.resolve()
			let resolvedFile = try fs.file(at: "/target")
			#expect(resolved.path == resolvedFile.path)
		}

		@Test(arguments: FSKind.allCases)
		func finderAliasInitFromNonAliasFileFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/file")
			#expect(throws: WrongNodeType.self) {
				try fs.finderAlias(at: "/file")
			}
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToNothingDuplicates(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			let original = try fs.createFinderAlias(at: "/alias", to: "/target")
			try original.copy(to: "/copied_alias")
			let copiedAlias = try fs.finderAlias(at: "/copied_alias")

			let resolvedOriginal = try original.resolve()
			let resolvedCopy = try copiedAlias.resolve()
			#expect(resolvedOriginal.path == "/target")
			#expect(resolvedCopy.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToFileReplaces(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			try fs.createFile(at: "/existing_file")
			try fs.replaceContentsOfFile(at: "/existing_file", to: "existing content")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")

			try alias.copy(to: "/existing_file")

			#expect(fs.nodeType(at: "/existing_file") == .finderAlias)
			let copiedAlias = try fs.finderAlias(at: "/existing_file")
			let resolved = try copiedAlias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToDirDuplicates(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try fs.createDir(at: "/dest_dir")

			try alias.copy(to: "/dest_dir")

			#expect(fs.nodeType(at: "/dest_dir/alias") == .finderAlias)
			let copiedAlias = try fs.finderAlias(at: "/dest_dir/alias")
			let resolved = try copiedAlias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToSymlinkReplaces(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/alias_target")
			try fs.createFile(at: "/symlink_target")
			try fs.createSymlink(at: "/symlink", to: "/symlink_target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/alias_target")

			try alias.copy(to: "/symlink")

			#expect(fs.nodeType(at: "/symlink") == .finderAlias)
			let copiedAlias = try fs.finderAlias(at: "/symlink")
			let resolved = try copiedAlias.resolve()
			#expect(resolved.path == "/alias_target")
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToAliasReplaces(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target1")
			try fs.createFile(at: "/target2")
			let alias1 = try fs.createFinderAlias(at: "/alias1", to: "/target1")
			try fs.createFinderAlias(at: "/alias2", to: "/target2")

			try alias1.copy(to: "/alias2")

			#expect(fs.nodeType(at: "/alias2") == .finderAlias)
			let copiedAlias = try fs.finderAlias(at: "/alias2")
			let resolved = try copiedAlias.resolve()
			#expect(resolved.path == "/target1")
		}

		@Test(arguments: FSKind.allCases)
		func copyFinderAliasToSymlinkToDirDuplicates(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			try fs.createDir(at: "/dest_dir")
			try fs.createSymlink(at: "/symlink_to_dir", to: "/dest_dir")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")

			try alias.copy(to: "/symlink_to_dir")

			#expect(fs.nodeType(at: "/dest_dir/alias") == .finderAlias)
			let copiedAlias = try fs.finderAlias(at: "/dest_dir/alias")
			let resolved = try copiedAlias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func moveFinderAliasRenames(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			var alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try alias.move(to: "/moved_alias")
			#expect(alias.path == "/moved_alias")
			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func moveFinderAliasToDirRehomes(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			var alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			let dir = try fs.createDir(at: "/dir")
			try alias.move(to: dir)
			#expect(alias.path == "/dir/alias")
			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
			#expect(fs.nodeType(at: "/alias") == nil)
		}

		@Test(arguments: FSKind.allCases)
		func renameFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			var alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try alias.rename(to: "renamed_alias")
			#expect(alias.path == "/renamed_alias")
			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributesOnFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let target = try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try alias.setExtendedAttribute(named: "user.test", to: "value")
			let retrievedValue = try alias.extendedAttributeString(named: "user.test")
			#expect(retrievedValue == "value")
			try #expect(target.extendedAttributeNames().isEmpty)
		}

		@Test(arguments: FSKind.allCases)
		func deleteFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try alias.delete()
			#expect(fs.nodeType(at: "/alias") == nil)
		}

		@Test(arguments: FSKind.allCases)
		func resolveFinderAliasToDir(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createDir(at: "/target_dir")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target_dir")
			let resolved = try alias.resolve()
			let targetDir = try fs.dir(at: "/target_dir")
			#expect(resolved.path == targetDir.path)
		}

		@Test(arguments: FSKind.allCases)
		func resolveFinderAliasToSymlink(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/real_file")
			try fs.createSymlink(at: "/symlink", to: "/real_file")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/symlink")
			let resolved = try alias.resolve()

			// Both mock and real FS follow aliases through symlinks to the final destination. This seems super weird to me, but it's what the official Darwin API does
			#expect(resolved.path == "/real_file")
		}

		@Test(arguments: FSKind.allCases)
		func resolveFinderAliasToAnotherFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			try fs.createFinderAlias(at: "/alias1", to: "/target")
			let alias2 = try fs.createFinderAlias(at: "/alias2", to: "/alias1")
			let resolved = try alias2.resolve()
			// Both mock and real FS follow alias chains to the final destination. This is weird, but less weird than what's happening in `resolveFinderAliasToSymlink`
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func resolvedFinderAliasUsesTargetPathAndName(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")

			#expect(try alias.destination == "/target")
			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
			#expect(resolved.name == "target")
		}

		// Finder Alias files should not be readable through contentsOf(file:) or sizeOfFile(at:)
		// because they contain opaque bookmark data that has no meaning outside of the
		// bookmark resolution APIs.

		@Test(arguments: FSKind.allCases)
		func contentsOfFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/target")
			try file.replaceContents("target content")
			try fs.createFinderAlias(at: "/alias", to: "/target")

			#expect(throws: WrongNodeType.self) {
				try fs.contentsOf(file: "/alias")
			}

			#expect(throws: WrongNodeType.self) {
				try fs.sizeOfFile(at: "/alias")
			}

			// Proving that the alias isn't broken; you just have to use it correctly
			let alias = try fs.finderAlias(at: "/alias")
			let resolved = try alias.resolve()
			#expect(resolved as? File == file)
			let targetContents = try file.stringContents()
			#expect(targetContents == "target content")
		}

		@Test(arguments: FSKind.allCases)
		func writeFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			try fs.replaceContentsOfFile(at: "/target", to: "initial content")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")

			#expect(throws: WrongNodeType.self) {
				try fs.replaceContentsOfFile(at: "/alias", to: "this should fail")
			}

			// The target file is unchanged
			let targetContents = try fs.contentsOf(file: "/target")
			#expect(String(data: targetContents, encoding: .utf8) == "initial content")

			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func finderAliasPointingToNonexistentTargetResolutionFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			try fs.createFinderAlias(at: "/alias", to: "/target")
			try fs.deleteNode(at: "/target")

			let alias = try fs.finderAlias(at: "/alias")
			#expect(throws: Error.self) {
				try alias.resolve()
			}
		}
	}
#endif

// MARK: - Special Nodes

extension DirsTests {
	private func makeSpecialNode(in fs: some FilesystemInterface) throws -> Special {
		let filename = "test_special"

		switch fs {
			case let mock as MockFSInterface:
				return try mock.createSpecialForTesting(at: "/\(filename)")

			case let real as RealFSInterface:
				let pathPrefix = real.chroot ?? "/tmp"
				let fifoPath = pathPrefix.appending(filename)
				guard mkfifo(fifoPath.string, 0o644) == 0 else {
					throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
				}
				return try real.special(at: "/\(filename)")

			default:
				fatalError("Unsupported FSInterface type")
		}
	}

	@Test(arguments: FSKind.allCases)
	func specialNodeBasics(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		var special = try makeSpecialNode(in: fs)

		// Verify detection
		#expect(fs.nodeType(at: "/test_special") == .special)
		#expect(fs.nodeTypeFollowingSymlinks(at: "/test_special") == .special)
		#expect(special.path == "/test_special")
		#expect(special.nodeType == .special)

		// Verify in children
		let children = try fs.rootDir.children()
		#expect(children.specials.count == 1)
		#expect(children.specials.first?.path == "/test_special")

		// Test rename and move
		try special.rename(to: "renamed")
		#expect(special.path == "/renamed")
		#expect(fs.nodeType(at: "/renamed") == .special)

		try fs.createDir(at: "/subdir")
		try special.move(to: "/subdir")
		#expect(special.path == "/subdir/renamed")

		// Verify allDescendantSpecials
		#expect(try Array(fs.rootDir.allDescendantSpecials()).count == 1)

		// Verify errors
		try fs.createFile(at: "/regular")
		#expect(throws: WrongNodeType.self) { try fs.special(at: "/regular") }
		#expect(throws: NoSuchNode.self) { try fs.special(at: "/nonexistent") }
	}
}

// MARK: - Extended Attributes

extension DirsTests {
	@Test(arguments: FSKind.allCases)
	func setAndGetExtendedAttribute(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		try file.setExtendedAttribute(named: "user.comment", to: Data("test comment".utf8))
		let retrieved = try file.extendedAttribute(named: "user.comment")
		#expect(retrieved == Data("test comment".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func getNonExistentExtendedAttributeReturnsNil(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		let retrieved = try file.extendedAttribute(named: "user.nonexistent")
		#expect(retrieved == nil)
	}

	@Test(arguments: FSKind.allCases)
	func listExtendedAttributes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		#expect(try file.extendedAttributeNames().isEmpty)

		try file.setExtendedAttribute(named: "user.attr1", to: Data("value1".utf8))
		try file.setExtendedAttribute(named: "user.attr2", to: Data("value2".utf8))
		try file.setExtendedAttribute(named: "user.attr3", to: Data("value3".utf8))

		let names = try file.extendedAttributeNames()
		#expect(names == ["user.attr1", "user.attr2", "user.attr3"])
	}

	@Test(arguments: FSKind.allCases)
	func removeExtendedAttribute(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		try file.setExtendedAttribute(named: "user.temp", to: Data("temporary".utf8))
		#expect(try file.extendedAttribute(named: "user.temp") != nil)

		try file.removeExtendedAttribute(named: "user.temp")

		#expect(try file.extendedAttribute(named: "user.temp") == nil)
		#expect(try file.extendedAttributeNames().isEmpty)
	}

	@Test(arguments: FSKind.allCases)
	func removeNonExistentExtendedAttributeSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		try file.removeExtendedAttribute(named: "user.doesnotexist")
	}

	@Test(arguments: FSKind.allCases)
	func updateExistingExtendedAttribute(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		try file.setExtendedAttribute(named: "user.counter", to: Data("1".utf8))
		try file.setExtendedAttribute(named: "user.counter", to: Data("2".utf8))
		#expect(try file.extendedAttribute(named: "user.counter") == Data("2".utf8))
	}

	@Test(arguments: FSKind.allCases)
	func extendedAttributeWithEmptyValue(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		try file.setExtendedAttribute(named: "user.empty", to: Data())

		let retrieved = try file.extendedAttribute(named: "user.empty")
		#expect(retrieved == Data())
	}

	@Test(arguments: FSKind.allCases)
	func extendedAttributeWithBinaryData(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		let binaryData = Data([0x00, 0xFF, 0x42, 0xAB, 0xCD, 0xEF])
		try file.setExtendedAttribute(named: "user.binary", to: binaryData)

		let retrieved = try file.extendedAttribute(named: "user.binary")
		#expect(retrieved == binaryData)
	}

	@Test(arguments: FSKind.allCases)
	func extendedAttributeNameTooLongThrows(fsKind: FSKind) throws {
		// Mock: use small custom limit to test configurability.
		// Real: use very large limit that exceeds any platform.
		let (fs, limit): (any FilesystemInterface, Int) = switch fsKind {
			case .mock:
				(MockFSInterface(maxExtendedAttributeNameLength: 10), 10)
			case .real:
				(self.fs(for: fsKind), 10_000)
		}

		let file = try fs.createFile(at: "/test")

		#if os(Linux)
			// On Linux, xattr names must be properly namespaced
			let longName = "user." + String(repeating: "a", count: limit + 1)
		#else
			let longName = String(repeating: "a", count: limit + 1)
		#endif

		#expect(throws: XAttrNameTooLong.self) {
			try file.setExtendedAttribute(named: longName, to: Data("value".utf8))
		}

		if case .mock = fsKind {
			#if os(Linux)
				let atLimitName = "user." + String(repeating: "b", count: limit - 5)
			#else
				let atLimitName = String(repeating: "b", count: limit)
			#endif
			#expect(throws: Never.self) {
				try file.setExtendedAttribute(named: atLimitName, to: Data("ok".utf8))
			}
		}
	}

	@Test(arguments: FSKind.allCases)
	func extendedAttributesOnDirectory(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let dir = try fs.createDir(at: "/testdir")

		try dir.setExtendedAttribute(named: "user.dirattr", to: Data("dir value".utf8))

		let retrieved = try dir.extendedAttribute(named: "user.dirattr")
		#expect(retrieved == Data("dir value".utf8))
	}

	// Despite the existence of lsetxattr/lgetxattr/etc., the Linux kernel VFS
	// prohibits user-namespaced xattrs on symlinks (security/system namespaced
	// xattrs can exist in special cases, but not the normal user.* variety).
	// From xattr(7): "User extended attributes may be assigned to files and
	// directories for storing arbitrary additional information..."
	// Symlinks are conspicuously absent. This is a Linux VFS policy due to
	// mandatory xattr namespacing. Operations return EOPNOTSUPP.
	#if !os(Linux)
		@Test(arguments: FSKind.allCases)
		func extendedAttributesOnSymlink(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let target = try fs.createFile(at: "/target")
			let symlink = try fs.createSymlink(at: "/link", to: "/target")

			let attrName = "user.linkattr"
			let value1 = Data("v1".utf8)
			let value2 = Data("v2".utf8)

			#expect(try symlink.extendedAttributeNames().isEmpty)
			#expect(try target.extendedAttributeNames().isEmpty)

			try symlink.setExtendedAttribute(named: attrName, to: value1)
			#expect(try symlink.extendedAttributeNames() == [attrName])
			#expect(try target.extendedAttributeNames().isEmpty)

			#expect(try symlink.extendedAttribute(named: attrName) == value1)
			#expect(try target.extendedAttribute(named: attrName) == nil)

			try symlink.setExtendedAttribute(named: attrName, to: value2)
			#expect(try symlink.extendedAttribute(named: attrName) == value2)
			#expect(try target.extendedAttribute(named: attrName) == nil)

			try symlink.removeExtendedAttribute(named: attrName)
			#expect(try symlink.extendedAttributeNames().isEmpty)
			#expect(try target.extendedAttributeNames().isEmpty)
		}
	#else // Linux
		@Test(arguments: FSKind.allCases)
		func linuxProhibitsUserNamespacedXattrsOnSymlinks(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			_ = try fs.createFile(at: "/target")

			let symlink = try fs.createSymlink(at: "/link", to: "/target")
			#expect(throws: (any Error).self) {
				try symlink.setExtendedAttribute(named: "user.test", to: "value")
			}

			let brokenSymlink = try fs.createSymlink(at: "/broken", to: "/nonexistent")
			#expect(throws: (any Error).self) {
				try brokenSymlink.setExtendedAttribute(named: "user.broken", to: "value")
			}
		}

		@Test(arguments: FSKind.allCases, NonResolvableNodeType.allCreatableCases)
		func linuxRequiresXattrNamespacing(fsKind: FSKind, nodeType: NonResolvableNodeType) throws {
			// On Linux, extended attribute names must be namespaced with one of:
			// - security.* (requires CAP_SYS_ADMIN)
			// - system.* (for specific uses like ACLs)
			// - trusted.* (requires CAP_SYS_ADMIN)
			// - user.* (available to all users on regular files/dirs)
			// Names without proper namespace prefix should fail with EOPNOTSUPP
			// See xattr(7) for details
			let fs = self.fs(for: fsKind)
			let node = try nodeType.createNonResolvableNode(at: "/test", in: fs)

			// Valid namespaced attribute should work
			#expect(throws: Never.self) {
				try node.setExtendedAttribute(named: "user.valid", to: "value")
			}

			// Invalid attribute names without proper namespace
			let invalidNames = [
				"nonamespace", // No namespace at all
				"invalid.name", // Invalid namespace
				"user", // Namespace without dot
				".leadingdot", // Leading dot without namespace
				"my.custom.namespace", // Custom namespace not in allowed set
			]

			for invalidName in invalidNames {
				#expect(throws: (any Error).self) {
					try node.setExtendedAttribute(named: invalidName, to: "test")
				}

				#expect(throws: (any Error).self) {
					_ = try node.extendedAttribute(named: invalidName)
				}
			}

			let validNames = try node.extendedAttributeNames()
			#expect(validNames == ["user.valid"])

			#expect(throws: Never.self) {
				try node.removeExtendedAttribute(named: "user.valid")
			}
		}
	#endif

	@Test(arguments: FSKind.allCases)
	func extendedAttributeStringConvenience(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		let attrName = "user.message"
		let attrValue = "hello world"

		try file.setExtendedAttribute(named: attrName, to: attrValue)
		#expect(try file.extendedAttributeString(named: attrName) == attrValue)

		let data = try #require(try file.extendedAttribute(named: attrName))
		#expect(data == Data(attrValue.utf8))
		#expect(String(data: data, encoding: .utf8) == attrValue)

		#expect(try file.extendedAttributeString(named: "user.nonexistent") == nil)
	}

	@Test(arguments: FSKind.allCases)
	func extendedAttributeStringInvalidUTF8Throws(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let file = try fs.createFile(at: "/test")

		let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
		try file.setExtendedAttribute(named: "user.invalid", to: invalidUTF8)

		#expect {
			try file.extendedAttributeString(named: "user.invalid")
		} throws: { error in
			guard let xattrError = error as? XAttrInvalidUTF8 else { return false }
			return xattrError.data == invalidUTF8
		}
	}
}
