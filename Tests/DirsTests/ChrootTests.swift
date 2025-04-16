import Dirs
import Foundation
import SystemPackage
import Testing

struct ChrootTests: ~Copyable {
	let tempDirPath: String
	let chrootFS: RealFSInterface

	init() throws {
		self.chrootFS = try RealFSInterface(chroot: .temporaryUnique())
		self.tempDirPath = self.chrootFS.chroot!.string
	}

	deinit {
		try? FileManager.default.removeItem(atPath: self.tempDirPath)
	}

	@Test(arguments: ["a", "b", "c"])
	func makesFile(named name: String) throws {
		try self.chrootFS.createFile(at: "/\(name)").replaceContents(name)

		let contentsFromFM = FileManager.default.contents(atPath: self.tempDirPath + "/\(name)")
		#expect(contentsFromFM == Data(name.utf8))
	}

	@Test func makesDeepDir() throws {
		try self.chrootFS.createFileAndIntermediaryDirs(at: "/a/b/c").replaceContents("c content")

		let contentsFromFM = FileManager.default.contents(atPath: self.tempDirPath + "/a/b/c")
		#expect(contentsFromFM == Data("c content".utf8))
	}
}
