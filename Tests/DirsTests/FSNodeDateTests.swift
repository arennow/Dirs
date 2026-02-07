import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	@Test(arguments: FSKind.allCases, NodeDateType.allCases)
	func dateForNonExistentNodeThrows(fsKind: FSKind, dateType: NodeDateType) throws {
		let fs = self.fs(for: fsKind)

		#expect(throws: (any Error).self) {
			_ = try fs.date(of: dateType, at: "/nonexistent")
		}
	}

	@Test(arguments: {
		var combinations: Array<(FSTests.FSKind, NodeType, NodeDateType)> = []
		for fsKind in FSTests.FSKind.allCases {
			for nodeType in NodeType.allCreatableCases {
				for dateType in NodeDateType.allCases {
					combinations.append((fsKind, nodeType, dateType))
				}
			}
		}
		return combinations
	}())
	func dateForNode(fsKind: FSKind, nodeType: NodeType, dateType: NodeDateType) throws {
		let fs = self.fs(for: fsKind)

		let (node, _) = try nodeType.createNode(at: "/node", in: fs)
		let date = try node.date(of: dateType)

		#expect(date != nil)
	}

	@Test(arguments: FSKind.allCases, NodeDateType.allCases)
	func dateForBrokenSymlink(fsKind: FSKind, dateType: NodeDateType) throws {
		let fs = self.fs(for: fsKind)

		let link = try fs.createSymlink(at: "/link", to: "/nonexistent")

		// Broken symlinks still have their own dates
		let date = try link.date(of: dateType)
		#expect(date != nil)
	}

	@Test(arguments: FSKind.allCases)
	func appendingToFileUpdatesModificationDate(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/file")
		try file.replaceContents("initial")

		#if XATTRS_ENABLED
			try file.setExtendedAttribute(named: "user.some_xattr", to: "exists")
		#endif

		func checkXattrUnaffected() throws {
			#if XATTRS_ENABLED
				// This is mainly a sanity check that the mock implementation doesn't overwrite
				// the whole metadata struct
				#expect(try file.extendedAttributeString(named: "user.some_xattr") == "exists")
			#endif
		}

		let initialModDate = try #require(try file.date(of: .modification))

		try file.appendContents(" appended")
		let updatedModDate1 = try #require(try file.date(of: .modification))
		#expect(updatedModDate1 > initialModDate)
		try checkXattrUnaffected()

		try file.replaceContents("replaced")
		let updatedModDate2 = try #require(try file.date(of: .modification))
		#expect(updatedModDate2 > updatedModDate1)
		try checkXattrUnaffected()
	}
}
