#if FINDER_ALIASES_ENABLED
	import Darwin
	import Foundation
	import SystemPackage

	extension RealFSInterface {
		/// Error indicating that no FinderInfo was available from `getattrlist()`.
		/// We need that to distinguish Finder aliases from regular files.
		/// It's usually stored in extended attributes (or in `._` files on non-xattr filesystems)
		/// so not all filesystems will provide it.
		struct NoFinderInfoAvailable: Error {}

		/// Classifies a filesystem node using a single `getattrlist()`.
		/// - Important: Uses `FSOPT_NOFOLLOW`, so symlinks are reported as `.symlink` (not the target’s type).
		/// - Throws: `POSIXError.ENOTDIR` or `POSIXError.ENOENT` for missing paths.
		/// - Throws: `NoFinderInfoAvailable` if `ATTR_CMN_FNDRINFO` is not returned by the filesystem.
		static func classifyPathKind_getattrlist(_ filePath: FilePath) throws -> NodeType {
			var alist = attrlist()
			alist.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
			alist.commonattr = UInt32(ATTR_CMN_OBJTYPE | ATTR_CMN_FNDRINFO) | ATTR_CMN_RETURNED_ATTRS

			// Stable layout even if some attrs are invalid; use RETURNED_ATTRS to know what is meaningful.
			let opts = UInt32(FSOPT_NOFOLLOW | FSOPT_PACK_INVAL_ATTRS)

			struct OutBuf {
				var length: UInt32 = 0
				var returned: attribute_set_t = .init()
				var objtype: fsobj_type_t = 0
				var fndrinfo: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
							   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
							   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
							   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
					(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
			}

			var out = OutBuf()

			let rc = withUnsafeMutablePointer(to: &alist) { alPtr in
				withUnsafeMutablePointer(to: &out) { outPtr in
					filePath.withPlatformString { filePathPlatString in
						getattrlist(filePathPlatString, alPtr, outPtr, MemoryLayout<OutBuf>.size, opts)
					}
				}
			}

			if rc != 0 {
				throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
			}

			// If FNDRINFO wasn't actually returned, require a fallback (e.g. Foundation URL mechanisms).
			if (out.returned.commonattr & UInt32(ATTR_CMN_FNDRINFO)) == 0 {
				throw NoFinderInfoAvailable()
			}

			switch out.objtype {
				case fsobj_type_t(VDIR.rawValue):
					return .dir
				case fsobj_type_t(VLNK.rawValue):
					return .symlink
				case fsobj_type_t(VREG.rawValue):
					// FileInfo layout: type[0..3], creator[4..7], finderFlags[8..9] (big-endian).
					let bytes = withUnsafeBytes(of: out.fndrinfo) { Array($0) }
					let finderFlagsBE = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
					let kIsAlias: UInt16 = 0x80_00
					return (finderFlagsBE & kIsAlias) != 0 ? .finderAlias : .file
				default:
					return .special
			}
		}
	}
#endif
