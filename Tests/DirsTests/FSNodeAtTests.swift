import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
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
