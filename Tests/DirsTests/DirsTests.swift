import Dirs
import DirsMockFSInterface
import Foundation
import SortAndFilter
import SystemPackage
import Testing

struct DirsTests: ~Copyable {
	let mockFS: any FilesystemInterface = MockFilesystemInterface.empty()
	let realFS: any FilesystemInterface
	let pathToDelete: FilePath?

	init() throws {
		let realFS = try RealFSInterface(chroot: .temporaryUnique())
		self.pathToDelete = realFS.chroot
		self.realFS = realFS
	}

	deinit {
		guard let pathToDelete = self.pathToDelete else { return }
		try? FileManager.default.removeItem(at: pathToDelete.url)
	}

	enum FSKind: CaseIterable { case mock, real }

	private func fs(for kind: FSKind) -> any FilesystemInterface {
		switch kind {
			case .mock: self.mockFS
			case .real: self.realFS
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

		let d = try Dir(fs: fs, path: "/")

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

		#expect(throws: Never.self) { try Dir(fs: fs, path: "/a") }
		try #expect(Dir(fs: fs, path: "/a/b/c/d") == created)

		#expect(throws: Never.self) { try fs.createDir(at: "/a/b/c/d") }
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
	func createExistingDir(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/a")

		#expect(throws: Never.self) { try fs.createDir(at: "/a") }
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

	// MARK: - Create File

	@Test(arguments: FSKind.allCases)
	func createFile(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let subDir = try fs.createDir(at: "/a")
		let createdFile = try subDir.createFile(at: "file")

		#expect(createdFile.path == "/a/file")
		#expect(throws: Never.self) { try File(fs: fs, path: "/a/file") }
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

		let root = try Dir(fs: fs, path: "/")
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

		try fs.rootDir.createFile(at: "a").replaceContents("content")

		let file = try fs.file(at: "/a")
		try file.replaceContents("new content")
		try #expect(file.stringContents() == "new content")
	}

	@Test(arguments: FSKind.allCases)
	func replaceContentsOfFileThroughBrokenSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createSymlink(at: "/s", to: "/a")
		#expect(throws: (any Error).self) { try fs.replaceContentsOfFile(at: "/s", to: "abc") }
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
	func createFileAndIntermediaryDirs(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		_ = try fs.createFileAndIntermediaryDirs(at: "/a/b/c/d/file1").replaceContents("contents 1")
		try #expect(fs.contentsOf(file: "/a/b/c/d/file1") == "contents 1".into())

		_ = try fs.createFileAndIntermediaryDirs(at: "/file2").replaceContents("contents 2")
		try #expect(fs.contentsOf(file: "/file2") == "contents 2".into())
	}

	@Test(arguments: FSKind.allCases, ["/new", "/existing"])
	func dirInitWithCreation(fsKind: FSKind, path: FilePath) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/existing")

		let firstTime = try Dir(fs: fs, path: path, createIfNeeded: true)
		let secondTime = try fs.dir(at: path)
		#expect(firstTime == secondTime)
	}

	@Test(arguments: FSKind.allCases)
	func dirInitNonExisting(fsKind: FSKind) {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			try Dir(fs: fs, path: "/a")
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
		try fs.createFileAndIntermediaryDirs(at: "/d/d1")
		try fs.createFileAndIntermediaryDirs(at: "/d/e/e1")

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

		try fs.rootDir.createDir(at: "d")

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
		try #expect(File(fs: fs, path: "/f2").stringContents() == "content")

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

		let d = try fs.createDir(at: "/d")
		try sym.move(to: d)
		#expect(sym.path == "/d/s2")
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
	func copyFileToFileDuplicates(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a").replaceContents("a content")
		try fs.copyNode(from: "/a", to: "/b")
		try #expect(fs.file(at: "/b").stringContents() == "a content")
	}

	@Test(arguments: FSKind.allCases)
	func copyFileToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createFile(at: "d")

		try fs.copyNode(from: "/c", to: "/d")

		try #expect(fs.file(at: "/c").stringContents() == "c content")
		try #expect(fs.file(at: "/d").stringContents() == "c content")
	}

	@Test(arguments: FSKind.allCases)
	func copyFileToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "c").replaceContents("c content")
		try fs.rootDir.createDir(at: "d")

		try fs.copyNode(from: "/c", to: "/d")

		try #expect(fs.file(at: "/c").stringContents() == "c content")
		try #expect(fs.file(at: "/d/c").stringContents() == "c content")
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToNothingRenames(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createDir(at: "d").createFile(at: "a").replaceContents("a content")

		try fs.copyNode(from: "/d", to: "/e")

		try #expect(fs.file(at: "/d/a").stringContents() == "a content")
		try #expect(fs.file(at: "/e/a").stringContents() == "a content")
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToFileReplaces(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.rootDir.createFile(at: "a")
		try fs.rootDir.createDir(at: "d")

		try fs.copyNode(from: "/d", to: "/a")

		try #expect(fs.rootDir.childDir(named: "d") != nil)
		try #expect(fs.rootDir.childDir(named: "a") != nil)
	}

	@Test(arguments: FSKind.allCases)
	func copyDirToDirRehomes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/a").replaceContents("a")
		try fs.createDir(at: "/d/b")
		try fs.createFile(at: "/d/b/c").replaceContents("c")
		try fs.createDir(at: "/e")

		try fs.copyNode(from: "/d", to: "/e")

		try #expect(fs.file(at: "/d/a").stringContents() == "a")
		try #expect(fs.file(at: "/d/b/c").stringContents() == "c")

		try #expect(fs.file(at: "/e/d/a").stringContents() == "a")
		try #expect(fs.file(at: "/e/d/b/c").stringContents() == "c")
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

	@Test(arguments: FSKind.allCases)
	func dirLookupTemporary(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let one = try fs.lookUpDir(.uniqueTemporary)
		let two = try fs.lookUpDir(.uniqueTemporary)

		#expect(one != two)
		#expect(one.path.string.localizedCaseInsensitiveContains("temporary"))
		#expect(two.path.string.localizedCaseInsensitiveContains("temporary"))
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
		try fs.createFileAndIntermediaryDirs(at: "/d/d1")

		try #expect(Set(fs.contentsOf(directory: "/")) == [
			.init(filePath: "/a", isDirectory: false),
			.init(filePath: "/b", isDirectory: false),
			.init(filePath: "/d", isDirectory: true),
		])

		try #expect(fs.contentsOf(directory: "/d") == [
			.init(filePath: "/d/d1", isDirectory: false),
		])
	}

	@Test(arguments: FSKind.allCases)
	func dirContentsSymlink(_ fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		try fs.createFileAndIntermediaryDirs(at: "/d/d1")
		try fs.createFileAndIntermediaryDirs(at: "/d/d2")
		try fs.createSymlink(at: "/s", to: "/d")

		try #expect(Set(fs.contentsOf(directory: "/")) == [
			.init(filePath: "/d", isDirectory: true),
			.init(filePath: "/s", isDirectory: true),
		])

		try #expect(Set(fs.contentsOf(directory: "/d")) == [
			.init(filePath: "/d/d1", isDirectory: false),
			.init(filePath: "/d/d2", isDirectory: false),
		])

		try #expect(Set(fs.contentsOf(directory: "/s")) == [
			.init(filePath: "/d/d1", isDirectory: false),
			.init(filePath: "/d/d2", isDirectory: false),
		])
	}
}

// MARK: - Descendant Nodes

extension DirsTests {
	private static func prepareForRecursiveNodesTests(_ fs: any FilesystemInterface) throws {
		try fs.createFileAndIntermediaryDirs(at: "/a1/a1f")
		try fs.createFileAndIntermediaryDirs(at: "/a1/a2f")
		try fs.createFileAndIntermediaryDirs(at: "/a1/a2/a1a2f")
		try fs.createFileAndIntermediaryDirs(at: "/a1/a2/a3/a1a2a3f")
		try fs.createFileAndIntermediaryDirs(at: "/b1/b2/b3/b1b2b3f")
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

		let f = try fs.createFileAndIntermediaryDirs(at: "/a/b/c/f")
		try f.replaceContents("abc")

		try fs.createSymlink(at: "/s", to: "/a/b")

		try #expect(fs.contentsOf(directory: "/s").compactMap(\.filePath.lastComponent) == ["c"])
		try #expect(fs.dir(at: "/s").children().directories.compactMap(\.path.lastComponent) == ["c"])
		#expect(throws: WrongNodeType.self) {
			try fs.file(at: "/s")
		}
	}

	@Test(arguments: FSKind.allCases)
	func nodesInsideSymlinkDirResolve(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createFileAndIntermediaryDirs(at: "/a/b/c1")
		try fs.createFileAndIntermediaryDirs(at: "/a/b/c2")
		try fs.createFileAndIntermediaryDirs(at: "/a/f")
		try fs.createSymlink(at: "/s", to: "/a")

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

		let d = try fs.dir(at: "/d")
		let descFile = try fs.file(at: "/d/e/e1")
		let a = try fs.file(at: "/a")

		try #expect(descFile.descendantPath(from: d) == "e/e1")
		try #expect(descFile.descendantPath(from: symlinks.dir) == "e/e1")
		try #expect(descFile.descendantPath(from: symlinks.dirSym) == "e/e1")

		#expect(throws: NodeNotDescendantError.self, performing: { try a.descendantPath(from: d) })
	}
}
