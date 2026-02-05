import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases, [DirLookupKind.documents, .cache, .home, .downloads])
	func dirLookupNonTemporary(_ fsKind: FSKind, dlk: DirLookupKind) throws {
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
