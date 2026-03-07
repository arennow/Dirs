import Dirs
import Foundation
import SystemPackage
import Testing

extension FSTests {
	func makeNonWritable(at ifp: some IntoFilePath, in fs: some FilesystemInterface) throws -> () -> Void {
		switch fs {
			case let mock as MockFSInterface:
				try mock.setWritableForTesting(at: ifp, writable: false)
				return {
					do {
						try mock.setWritableForTesting(at: ifp, writable: true)
					} catch {
						Issue.record("Failed to restore writability in MockFSInterface: \(error)")
					}
				}

			case let real as RealFSInterface:
				return try real.setWritableForTesting(at: ifp, writable: false)

			default:
				fatalError("Unsupported FSInterface type")
		}
	}

	// MARK: - File content writes

	@Test(arguments: FSKind.allCases)
	func writeToNonWritableFileFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/f")
		try file.replaceContents("original")
		let restore = try makeNonWritable(at: "/f", in: fs)
		defer { restore() }

		#expect(throws: PermissionDenied(path: "/f")) {
			try file.replaceContents("new content")
		}
		#expect(throws: PermissionDenied(path: "/f")) {
			try fs.appendContentsOfFile(at: file, with: Data("extra".utf8))
		}

		try #expect(file.stringContents() == "original")
	}

	// MARK: - Extended attributes on non-writable file

	#if XATTRS_ENABLED
		@Test(arguments: FSKind.allCases)
		func xattrOnNonWritableFileFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			let file = try fs.createFile(at: "/f")
			let xattrName = "user.test"
			try file.setExtendedAttribute(named: xattrName, to: "original")

			let restore = try makeNonWritable(at: "/f", in: fs)
			defer { restore() }

			#expect(throws: PermissionDenied(path: "/f")) {
				try file.setExtendedAttribute(named: xattrName, to: "denied")
			}
			#expect(throws: PermissionDenied(path: "/f")) {
				try file.removeExtendedAttribute(named: xattrName)
			}

			try #expect(file.extendedAttributeString(named: xattrName) == "original")
		}
	#endif

	// MARK: - Non-writable directory

	#if !os(Windows)
		@Test(arguments: FSKind.allCases)
		func createInNonWritableDirFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			try fs.createDir(at: "/d")
			let restore = try makeNonWritable(at: "/d", in: fs)
			defer { restore() }

			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.createFile(at: "/d/child")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.createDir(at: "/d/child")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.createSymlink(at: "/d/link", to: "/somewhere")
			}
		}

		@Test(arguments: FSKind.allCases)
		func mutateNonWritableDirFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			try fs.createDir(at: "/d")
			try fs.createFile(at: "/d/f")
			try fs.createFile(at: "/src")
			let restore = try makeNonWritable(at: "/d", in: fs)
			defer { restore() }

			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.deleteNode(at: "/d/f")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.copyNode(from: "/src", to: "/d")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.moveNode(from: "/src", to: "/d")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.moveNode(from: "/d/f", to: "/elsewhere")
			}
			#expect(throws: PermissionDenied(path: "/d")) {
				try fs.renameNode(at: "/d/f", to: "newname")
			}
		}

		// MARK: - Non-writable directory through symlink

		@Test(arguments: FSKind.allCases)
		func createThroughSymlinkToNonWritableDirFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			try fs.createDir(at: "/d")
			try fs.createSymlink(at: "/s", to: "/d")
			let restore = try makeNonWritable(at: "/d", in: fs)
			defer { restore() }

			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.createFile(at: "/s/child")
			}
			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.createDir(at: "/s/child")
			}
			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.createSymlink(at: "/s/link", to: "/somewhere")
			}
		}

		@Test(arguments: FSKind.allCases)
		func mutateThroughSymlinkToNonWritableDirFails(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)

			try fs.createDir(at: "/d")
			try fs.createFile(at: "/d/f")
			try fs.createSymlink(at: "/s", to: "/d")
			try fs.createFile(at: "/src")
			let restore = try makeNonWritable(at: "/d", in: fs)
			defer { restore() }

			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.deleteNode(at: "/s/f")
			}
			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.copyNode(from: "/src", to: "/s")
			}
			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.moveNode(from: "/src", to: "/s")
			}
			#expect(throws: PermissionDenied(path: "/s")) {
				try fs.moveNode(from: "/s/f", to: "/elsewhere")
			}
		}

	#endif

	// MARK: - Non-writable file through symlink

	@Test(arguments: FSKind.allCases)
	func writeToNonWritableFileThroughSymlinkFails(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/f")
		try file.replaceContents("original")
		try fs.createSymlink(at: "/s", to: "/f")
		let restore = try makeNonWritable(at: "/f", in: fs)
		defer { restore() }

		#expect(throws: PermissionDenied(path: "/s")) {
			try fs.replaceContentsOfFile(at: "/s", to: Data("denied".utf8))
		}
		#expect(throws: PermissionDenied(path: "/s")) {
			try fs.appendContentsOfFile(at: "/s", with: Data("denied".utf8))
		}

		try #expect(file.stringContents() == "original")
	}

	// MARK: - Reading from non-writable nodes still works

	@Test(arguments: FSKind.allCases)
	func readNonWritableFileSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/f")
		try file.replaceContents("hello")

		let restore = try makeNonWritable(at: "/f", in: fs)
		defer { restore() }

		try #expect(file.stringContents() == "hello")
	}

	@Test(arguments: FSKind.allCases)
	func listNonWritableDirSucceeds(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		try fs.createDir(at: "/d")
		try fs.createFile(at: "/d/f")

		let restore = try makeNonWritable(at: "/d", in: fs)
		defer { restore() }

		let dir = try fs.dir(at: "/d")
		let children = try dir.children()
		#expect(children.files.count == 1)
	}

	// MARK: - Restoring writability works

	@Test(arguments: FSKind.allCases)
	func restoreWritabilityAllowsMutation(fsKind: FSKind) throws {
		let fs = self.fs(for: fsKind)

		let file = try fs.createFile(at: "/f")
		let restore = try makeNonWritable(at: "/f", in: fs)

		#expect(throws: PermissionDenied(path: "/f")) {
			try file.replaceContents("denied")
		}

		restore()

		#expect(throws: Never.self) {
			try file.replaceContents("allowed")
		}
		try #expect(file.stringContents() == "allowed")
	}
}
