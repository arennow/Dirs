import Dirs
import Foundation
import SystemPackage
import Testing

#if XATTRS_ENABLED
	extension FSTests {
		@Test(arguments: FSKind.allCases)
		func setAndGetExtendedAttribute(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			try file.setExtendedAttribute(named: "user.comment", to: Data("test comment".utf8))
			let retrieved = try file.extendedAttribute(named: "user.comment")
			#expect(retrieved == Data("test comment".utf8))
		}

		@Test(arguments: FSKind.allCases)
		func getNonExistentExtendedAttributeReturnsNil(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			let retrieved = try file.extendedAttribute(named: "user.nonexistent")
			#expect(retrieved == nil)
		}

		@Test(arguments: FSKind.allCases)
		func listExtendedAttributes(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			#expect(try file.extendedAttributeNames().isEmpty)

			try file.setExtendedAttribute(named: "user.attr1", to: Data("value1".utf8))
			try file.setExtendedAttribute(named: "user.attr2", to: Data("value2".utf8))
			try file.setExtendedAttribute(named: "user.attr3", to: Data("value3".utf8))

			let names = try file.extendedAttributeNames()
			#expect(names == ["user.attr1", "user.attr2", "user.attr3"])
		}

		@Test(arguments: FSKind.allCases)
		func removeExtendedAttribute(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			try file.setExtendedAttribute(named: "user.temp", to: Data("temporary".utf8))
			#expect(try file.extendedAttribute(named: "user.temp") != nil)

			try file.removeExtendedAttribute(named: "user.temp")

			#expect(try file.extendedAttribute(named: "user.temp") == nil)
			#expect(try file.extendedAttributeNames().isEmpty)
		}

		@Test(arguments: FSKind.allCases)
		func removeNonExistentExtendedAttributeSucceeds(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			try file.removeExtendedAttribute(named: "user.doesnotexist")
		}

		@Test(arguments: FSKind.allCases)
		func updateExistingExtendedAttribute(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			try file.setExtendedAttribute(named: "user.counter", to: Data("1".utf8))
			try file.setExtendedAttribute(named: "user.counter", to: Data("2".utf8))
			#expect(try file.extendedAttribute(named: "user.counter") == Data("2".utf8))
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributeWithEmptyValue(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			try file.setExtendedAttribute(named: "user.empty", to: Data())

			let retrieved = try file.extendedAttribute(named: "user.empty")
			#expect(retrieved == Data())
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributeWithBinaryData(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			let binaryData = Data([0x00, 0xFF, 0x42, 0xAB, 0xCD, 0xEF])
			try file.setExtendedAttribute(named: "user.binary", to: binaryData)

			let retrieved = try file.extendedAttribute(named: "user.binary")
			#expect(retrieved == binaryData)
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributeNameTooLongThrows(fsKind: FSKind) throws {
			// Mock: use small custom limit to test configurability.
			// Real: use very large limit that exceeds any platform.
			let (fs, limit): (any FilesystemInterface, Int) = switch fsKind {
				case .mock:
					(MockFSInterface(maxExtendedAttributeNameLength: 10), 10)
				case .real:
					(self.fs(for: fsKind), 10_000)
			}

			let file = try fs.createFile(at: "/test")

			#if os(Linux)
				// On Linux, xattr names must be properly namespaced
				let longName = "user." + String(repeating: "a", count: limit + 1)
			#else
				let longName = String(repeating: "a", count: limit + 1)
			#endif

			#expect(throws: XAttrNameTooLong.self) {
				try file.setExtendedAttribute(named: longName, to: Data("value".utf8))
			}

			if case .mock = fsKind {
				#if os(Linux)
					let atLimitName = "user." + String(repeating: "b", count: limit - 5)
				#else
					let atLimitName = String(repeating: "b", count: limit)
				#endif
				#expect(throws: Never.self) {
					try file.setExtendedAttribute(named: atLimitName, to: Data("ok".utf8))
				}
			}
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributesOnDirectory(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let dir = try fs.createDir(at: "/testdir")

			try dir.setExtendedAttribute(named: "user.dirattr", to: Data("dir value".utf8))

			let retrieved = try dir.extendedAttribute(named: "user.dirattr")
			#expect(retrieved == Data("dir value".utf8))
		}

		// Despite the existence of lsetxattr/lgetxattr/etc., the Linux kernel VFS
		// prohibits user-namespaced xattrs on symlinks (security/system namespaced
		// xattrs can exist in special cases, but not the normal user.* variety).
		// From xattr(7): "User extended attributes may be assigned to files and
		// directories for storing arbitrary additional information..."
		// Symlinks are conspicuously absent. This is a Linux VFS policy due to
		// mandatory xattr namespacing. Operations return EOPNOTSUPP.
		#if !os(Linux)
			@Test(arguments: FSKind.allCases)
			func extendedAttributesOnSymlink(fsKind: FSKind) throws {
				let fs = self.fs(for: fsKind)
				let target = try fs.createFile(at: "/target")
				let symlink = try fs.createSymlink(at: "/link", to: "/target")

				let attrName = "user.linkattr"
				let value1 = Data("v1".utf8)
				let value2 = Data("v2".utf8)

				#expect(try symlink.extendedAttributeNames().isEmpty)
				#expect(try target.extendedAttributeNames().isEmpty)

				try symlink.setExtendedAttribute(named: attrName, to: value1)
				#expect(try symlink.extendedAttributeNames() == [attrName])
				#expect(try target.extendedAttributeNames().isEmpty)

				#expect(try symlink.extendedAttribute(named: attrName) == value1)
				#expect(try target.extendedAttribute(named: attrName) == nil)

				try symlink.setExtendedAttribute(named: attrName, to: value2)
				#expect(try symlink.extendedAttribute(named: attrName) == value2)
				#expect(try target.extendedAttribute(named: attrName) == nil)

				try symlink.removeExtendedAttribute(named: attrName)
				#expect(try symlink.extendedAttributeNames().isEmpty)
				#expect(try target.extendedAttributeNames().isEmpty)
			}
		#else // Linux
			@Test(arguments: FSKind.allCases)
			func linuxProhibitsUserNamespacedXattrsOnSymlinks(fsKind: FSKind) throws {
				let fs = self.fs(for: fsKind)
				_ = try fs.createFile(at: "/target")

				let symlink = try fs.createSymlink(at: "/link", to: "/target")
				#expect(throws: (any Error).self) {
					try symlink.setExtendedAttribute(named: "user.test", to: "value")
				}

				let brokenSymlink = try fs.createSymlink(at: "/broken", to: "/nonexistent")
				#expect(throws: (any Error).self) {
					try brokenSymlink.setExtendedAttribute(named: "user.broken", to: "value")
				}
			}

			@Test(arguments: FSKind.allCases, NonResolvableNodeType.allCreatableCases)
			func linuxRequiresXattrNamespacing(fsKind: FSKind, nodeType: NonResolvableNodeType) throws {
				// On Linux, extended attribute names must be namespaced with one of:
				// - security.* (requires CAP_SYS_ADMIN)
				// - system.* (for specific uses like ACLs)
				// - trusted.* (requires CAP_SYS_ADMIN)
				// - user.* (available to all users on regular files/dirs)
				// Names without proper namespace prefix should fail with EOPNOTSUPP
				// See xattr(7) for details
				let fs = self.fs(for: fsKind)
				let node = try nodeType.createNonResolvableNode(at: "/test", in: fs)

				// Valid namespaced attribute should work
				#expect(throws: Never.self) {
					try node.setExtendedAttribute(named: "user.valid", to: "value")
				}

				// Invalid attribute names without proper namespace
				let invalidNames = [
					"nonamespace", // No namespace at all
					"invalid.name", // Invalid namespace
					"user", // Namespace without dot
					".leadingdot", // Leading dot without namespace
					"my.custom.namespace", // Custom namespace not in allowed set
				]

				for invalidName in invalidNames {
					#expect(throws: (any Error).self) {
						try node.setExtendedAttribute(named: invalidName, to: "test")
					}

					#expect(throws: (any Error).self) {
						_ = try node.extendedAttribute(named: invalidName)
					}
				}

				let validNames = try node.extendedAttributeNames()
				#expect(validNames == ["user.valid"])

				#expect(throws: Never.self) {
					try node.removeExtendedAttribute(named: "user.valid")
				}
			}
		#endif

		@Test(arguments: FSKind.allCases)
		func extendedAttributeStringConvenience(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			let attrName = "user.message"
			let attrValue = "hello world"

			try file.setExtendedAttribute(named: attrName, to: attrValue)
			#expect(try file.extendedAttributeString(named: attrName) == attrValue)

			let data = try #require(try file.extendedAttribute(named: attrName))
			#expect(data == Data(attrValue.utf8))
			#expect(String(data: data, encoding: .utf8) == attrValue)

			#expect(try file.extendedAttributeString(named: "user.nonexistent") == nil)
		}

		@Test(arguments: FSKind.allCases)
		func extendedAttributeStringInvalidUTF8Throws(fsKind: FSKind) throws {
			let fs = self.fs(for: fsKind)
			let file = try fs.createFile(at: "/test")

			let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
			try file.setExtendedAttribute(named: "user.invalid", to: invalidUTF8)

			#expect {
				try file.extendedAttributeString(named: "user.invalid")
			} throws: { error in
				guard let xattrError = error as? XAttrInvalidUTF8 else { return false }
				return xattrError.data == invalidUTF8
			}
		}
	}
#endif
