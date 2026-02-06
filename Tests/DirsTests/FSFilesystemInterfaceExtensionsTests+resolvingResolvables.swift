import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases)
	func resolvingResolvablesReturnsNodeTypes(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let file = try root.createFile(at: "file.txt")
		let dir = try root.createDir(at: "mydir")

		#expect(fs.nodeTypeResolvingResolvables(at: file) == .file)
		#expect(fs.nodeTypeResolvingResolvables(at: dir) == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func resolvingResolvablesFollowsSymlinks(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let target = try root.createFile(at: "target.txt")
		let targetDir = try root.createDir(at: "targetdir")
		let link = try root.createSymlink(at: "link", to: target)
		let link1 = try root.createSymlink(at: "link1", to: "link2")
		_ = try root.createSymlink(at: "link2", to: "link3")
		_ = try root.createSymlink(at: "link3", to: targetDir)

		#expect(fs.nodeTypeResolvingResolvables(at: link) == .file)
		#expect(fs.nodeTypeResolvingResolvables(at: link1) == .dir)
	}

	@Test(arguments: FSKind.allCases)
	func resolvingResolvablesFollowsRelativeSymlink(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let dir = try root.createDir(at: "dir")
		let target = try dir.createFile(at: "target.txt")
		let link = try dir.createSymlink(at: "link", to: target)

		#expect(fs.nodeTypeResolvingResolvables(at: link) == .file)
	}

	@Test(arguments: FSKind.allCases)
	func resolvingResolvablesReturnsNilForCircularSymlinks(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let link1 = try root.createSymlink(at: "link1", to: "link2")
		_ = try root.createSymlink(at: "link2", to: "link1")
		let a = try root.createSymlink(at: "a", to: "b")
		_ = try root.createSymlink(at: "b", to: "c")
		_ = try root.createSymlink(at: "c", to: "a")

		#expect(fs.nodeTypeResolvingResolvables(at: link1) == nil)
		#expect(fs.nodeTypeResolvingResolvables(at: a) == nil)
	}

	@Test(arguments: FSKind.allCases)
	func resolvingResolvablesReturnsNilForErrors(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)
		let root = try fs.rootDir
		let broken = try root.createSymlink(at: "broken", to: "nonexistent")

		#expect(fs.nodeTypeResolvingResolvables(at: "/nonexistent") == nil)
		#expect(fs.nodeTypeResolvingResolvables(at: broken) == nil)
	}

	#if FINDER_ALIASES_ENABLED
		@Test(arguments: FSKind.allCases)
		func resolvingResolvablesFollowsFinderAliases(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let root = try fs.rootDir
			let target = try root.createFile(at: "target.txt")
			let targetDir = try root.createDir(at: "targetdir")
			let alias = try root.createFinderAlias(at: "alias", to: target)
			let alias2 = try root.createFinderAlias(at: "alias2", to: targetDir)

			#expect(fs.nodeTypeResolvingResolvables(at: alias) == .file)
			#expect(fs.nodeTypeResolvingResolvables(at: alias2) == .dir)
		}

		@Test(arguments: FSKind.allCases)
		func resolvingResolvablesFollowsMixedChains(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let root = try fs.rootDir
			let target = try root.createFile(at: "target.txt")
			let targetDir = try root.createDir(at: "targetdir")
			let link = try root.createSymlink(at: "link", to: target)
			let alias1 = try root.createFinderAlias(at: "alias1", to: targetDir)
			let alias2 = try root.createFinderAlias(at: "alias2", to: link)
			let link2 = try root.createSymlink(at: "link2", to: alias1)

			#expect(fs.nodeTypeResolvingResolvables(at: alias2) == .file)
			#expect(fs.nodeTypeResolvingResolvables(at: link2) == .dir)
		}

		@Test(arguments: FSKind.allCases)
		func resolvingResolvablesReturnsNilForAliasErrors(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let root = try fs.rootDir
			let s1 = try root.createSymlink(at: "s1", to: "s2")
			_ = try root.createSymlink(at: "s2", to: "s1")
			let alias1 = try root.createFinderAlias(at: "alias1", to: s1)
			let target = try root.createFile(at: "target.txt")
			let alias2 = try root.createFinderAlias(at: "alias2", to: target)
			try target.delete()

			#expect(fs.nodeTypeResolvingResolvables(at: alias1) == nil)
			#expect(fs.nodeTypeResolvingResolvables(at: alias2) == nil)
		}
	#endif
}
