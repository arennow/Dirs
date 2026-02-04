import Dirs
import Foundation
import SystemPackage
import Testing

#if canImport(Darwin)
	extension FSTests {
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
			let targetFile = try fs.rootDir.createFile(at: "target")
			try targetFile.replaceContents("initial content")
			let alias = try fs.rootDir.createFinderAlias(at: "alias", to: targetFile)

			#expect(throws: WrongNodeType.self) {
				try fs.replaceContentsOfFile(at: alias, to: "this should fail")
			}

			// The target file is unchanged
			let targetContents = try fs.contentsOf(file: "/target")
			#expect(String(data: targetContents, encoding: .utf8) == "initial content")

			let resolved = try alias.resolve()
			#expect(resolved.path == "/target")
		}

		@Test(arguments: FSKind.allCases)
		func detectsMissingTargetWhenResolvingFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createFile(at: "/target")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/target")
			try fs.deleteNode(at: "/target")
			#expect(throws: NoSuchNode.self) {
				try alias.resolve()
			}
		}

		@Test(arguments: FSKind.allCases)
		func detectsCircularSymlinksWhenResolvingFinderAlias(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			try fs.createSymlink(at: "/s1", to: "/s2")
			try fs.createSymlink(at: "/s2", to: "/s1")
			let alias = try fs.createFinderAlias(at: "/alias", to: "/s1")
			#expect(throws: NoSuchNode.self) {
				try alias.resolve()
			}
		}
	}
#endif
