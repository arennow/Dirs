import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func resolvedDescendantSequencesResolveSymlinksAndRecurseIntoResolvedDirs(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let observed = try root.createDir(at: "observed")
		let nestedDir = try observed.createDir(at: "nested")
		_ = try nestedDir.createFile(at: "child.txt")
		let rootFile = try observed.createFile(at: "root.txt")
		let dirLink = try observed.createSymlink(at: "dir_link", to: nestedDir)
		_ = try observed.createSymlink(at: "file_link", to: rootFile)
		_ = try observed.createSymlink(at: "dir_chain", to: dirLink)

		let nodePaths = Set(observed.allResolvedDescendantNodes().map(\.path))
		let filePaths = Set(observed.allResolvedDescendantFiles().map(\.path))
		let dirPaths = Set(observed.allResolvedDescendantDirs().map(\.path))

		#expect(nodePaths == [
			"/observed/nested",
			"/observed/nested/child.txt",
			"/observed/root.txt",
			"/observed/file_link",
			"/observed/dir_link",
			"/observed/dir_link/child.txt",
			"/observed/dir_chain",
			"/observed/dir_chain/child.txt",
		])
		#expect(filePaths == [
			"/observed/nested/child.txt",
			"/observed/root.txt",
			"/observed/file_link",
			"/observed/dir_link/child.txt",
			"/observed/dir_chain/child.txt",
		])
		#expect(dirPaths == [
			"/observed/nested",
			"/observed/dir_link",
			"/observed/dir_chain",
		])
	}

	@Test(arguments: FSKind.allCases)
	func resolvedDescendantSequencesSkipBrokenAndCircularResolvables(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let observed = try root.createDir(at: "observed")
		let keptDir = try observed.createDir(at: "kept")
		_ = try keptDir.createFile(at: "survivor.txt")
		_ = try observed.createSymlink(at: "broken", to: "/missing")
		let loop1 = try observed.createSymlink(at: "loop1", to: "loop2")
		_ = try observed.createSymlink(at: "loop2", to: "loop1")
		let chainA = try observed.createSymlink(at: "chain_a", to: "chain_b")
		_ = try observed.createSymlink(at: "chain_b", to: "chain_c")
		_ = try observed.createSymlink(at: "chain_c", to: "chain_a")

		let nodePaths = Set(observed.allResolvedDescendantNodes().map(\.path))
		let filePaths = Set(observed.allResolvedDescendantFiles().map(\.path))
		let dirPaths = Set(observed.allResolvedDescendantDirs().map(\.path))

		#expect(nodePaths.contains("/observed/kept"))
		#expect(nodePaths.contains("/observed/kept/survivor.txt"))
		#expect(nodePaths.contains("/observed/broken") == false)
		#expect(nodePaths.contains(loop1.path) == false)
		#expect(nodePaths.contains(chainA.path) == false)
		#expect(filePaths == ["/observed/kept/survivor.txt"])
		#expect(dirPaths == ["/observed/kept"])
	}

	@Test(arguments: FSKind.allCases)
	func resolvedDescendantSequencesPreserveDistinctDescendantPaths(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let observed = try root.createDir(at: "observed")
		let target = try observed.createFile(at: "target.txt")
		_ = try observed.createSymlink(at: "link_a", to: target)
		_ = try observed.createSymlink(at: "link_b", to: target)

		let filePaths = Array(observed.allResolvedDescendantFiles().map(\.path))

		#expect(Set(filePaths) == [
			"/observed/target.txt",
			"/observed/link_a",
			"/observed/link_b",
		])
		#expect(filePaths.count == 3)
	}

	#if SPECIALS_ENABLED
		@Test(arguments: FSKind.allCases)
		func resolvedDescendantSpecialSequenceResolvesSymlinks(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let root = try fs.rootDir
			let observed = try root.createDir(at: "observed")
			let special = try self.createSpecialNode(named: "resolved-special", in: fs)
			_ = try observed.createSymlink(at: "special_link", to: special)

			let specialPaths = Set(observed.allResolvedDescendantSpecials().map(\.path))

			#expect(specialPaths == ["/observed/special_link"])
		}
	#endif

	#if FINDER_ALIASES_ENABLED
		@Test(arguments: FSKind.allCases)
		func resolvedDescendantSequencesResolveFinderAliases(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let root = try fs.rootDir
			let observed = try root.createDir(at: "observed")
			let targetFile = try observed.createFile(at: "target.txt")
			let targetDir = try observed.createDir(at: "target-dir")
			_ = try targetDir.createFile(at: "nested.txt")
			_ = try observed.createFinderAlias(at: "alias_to_file", to: targetFile)
			_ = try observed.createFinderAlias(at: "alias_to_dir", to: targetDir)

			let filePaths = Set(observed.allResolvedDescendantFiles().map(\.path))
			let dirPaths = Set(observed.allResolvedDescendantDirs().map(\.path))

			#expect(filePaths.contains("/observed/alias_to_file"))
			#expect(filePaths.contains("/observed/target-dir/nested.txt"))
			#expect(dirPaths.contains("/observed/alias_to_dir"))
		}
	#endif
}
