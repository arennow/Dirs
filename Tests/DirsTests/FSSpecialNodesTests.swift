import Dirs
import Foundation
import SortAndFilter
import SystemPackage
import Testing

extension FSTests {
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
