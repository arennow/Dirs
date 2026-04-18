#if FINDER_ALIASES_ENABLED
	import Darwin
	import Foundation
	import SystemPackage

	// vnode type constants from <sys/vnode.h>, which is not available on iOS.
	// These are stable kernel ABI values, so we can hardcode them here.
	private let _VREG = fsobj_type_t(1)
	private let _VDIR = fsobj_type_t(2)
	private let _VLNK = fsobj_type_t(5)

	// kIsAlias bit in the big-endian finderFlags word (bytes 8–9 of FileInfo / FolderInfo).
	private let kIsAlias: UInt16 = 0x80_00

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
						getattrlist(filePathPlatString, alPtr, outPtr, MemoryLayout<OutBuf>.size, numericCast(opts))
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
				case _VDIR:
					return .dir
				case _VLNK:
					return .symlink
				case _VREG:
					// FileInfo layout: type[0..3], creator[4..7], finderFlags[8..9] (big-endian).
					let bytes = withUnsafeBytes(of: out.fndrinfo) { Array($0) }
					let finderFlagsBE = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
					return (finderFlagsBE & kIsAlias) != 0 ? .finderAlias : .file
				default:
					return .special
			}
		}

		/// Enumerates the immediate children of a directory using `getattrlistbulk(2)`.
		///
		/// Unlike `FileManager.contentsOfDirectory`, this does **not** suppress `._`-prefixed
		/// (AppleDouble resource-fork companion) files. It retrieves filename, vnode type, and
		/// FinderInfo for every entry in bulk kernel calls with no per-entry follow-up syscalls.
		///
		/// - Returns: One `(name, nodeType)` pair per immediate child. The `nodeType` is `nil`
		///   for regular files on filesystems that did not return `ATTR_CMN_FNDRINFO` — the caller
		///   must use a Foundation fallback to distinguish `.file` from `.finderAlias` in that case.
		/// - Throws: A `POSIXError` if the directory cannot be opened or read.
		static func contentsOfDirectory_getattrlistbulk(rawPath: FilePath) throws -> Array<(name: String, nodeType: NodeType?)> {
			let fd = rawPath.withPlatformString { open($0, O_RDONLY | O_DIRECTORY) }
			guard fd >= 0 else {
				throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
			}
			defer {
				// We swallow the error case here because:
				// 1. This is a readonly fd, so there's no risk of losing flush-on-close data
				// 2. There's nothing (besides logging) to do with an error
				// 3. Linux and Darwin both claim to unconditionally remove fd from the descriptor table, even on error
				Darwin.close(fd)
			}

			// Request: RETURNED_ATTRS (required by getattrlistbulk) + name + objtype + fndrinfo.
			// FSOPT_PACK_INVAL_ATTRS keeps the per-entry buffer layout constant regardless of
			// which attrs a given filesystem provides — missing attrs are zeroed, not omitted.
			// We still read the returned field per-entry to know whether FNDRINFO was actually
			// provided (zeroed-and-provided is indistinguishable from zeroed-because-absent
			// without checking it).
			var alist = attrlist()
			alist.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
			alist.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_FNDRINFO)

			// 256 KB typically fits 4 000+ entries per call, covering most real-world
			// directories without looping.
			let bufferSize = 256 * 1024
			let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
			defer { buffer.deallocate() }

			var results = Array<(name: String, nodeType: NodeType?)>()

			while true {
				let entryCount = getattrlistbulk(fd, &alist, buffer, bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
				guard entryCount >= 0 else {
					throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
				}
				if entryCount == 0 { break }

				var cursor = UnsafeRawPointer(buffer)

				for _ in 0..<entryCount {
					let entryBase = cursor

					// Per-entry layout (all fields 4-byte-aligned):
					//  [0 ] uint32_t        length          — total record size including this field
					//  [4 ] attribute_set_t returned        — which attrs were actually provided (5 × uint32_t = 20 bytes)
					//  [24] attrreference_t name            — { int32_t offset_from_here, uint32_t len_incl_null }
					//  [32] fsobj_type_t    objtype
					//  [36] uint8_t[32]     fndrinfo        — zeroed when not provided by the filesystem

					let entryLength = cursor.load(as: UInt32.self)
					cursor = cursor.advanced(by: 4)

					let returned = cursor.load(as: attribute_set_t.self)
					cursor = cursor.advanced(by: MemoryLayout<attribute_set_t>.size)

					// The name string lives at nameRefBase + nameDataOffset.
					let nameRefBase = cursor
					let nameDataOffset = cursor.load(as: Int32.self)
					let nameLenInclNull = cursor.advanced(by: 4).load(as: UInt32.self)
					cursor = cursor.advanced(by: 8) // sizeof(attrreference_t)

					let objtype = cursor.load(as: fsobj_type_t.self)
					cursor = cursor.advanced(by: 4)

					// fndrinfo: 32 bytes; cursor advancement past it is skipped because we
					// jump directly to entryBase + entryLength at the end of the loop body.
					let fndrInfoBase = cursor

					let nameBytes = max(0, Int(nameLenInclNull) - 1) // exclude null terminator
					let namePtr = nameRefBase.advanced(by: Int(nameDataOffset))
					let name = String(bytes: UnsafeRawBufferPointer(start: namePtr, count: nameBytes),
									  encoding: .utf8)
						?? String(cString: namePtr.assumingMemoryBound(to: CChar.self))

					let nodeType: NodeType?
					switch objtype {
						case _VDIR:
							nodeType = .dir
						case _VLNK:
							nodeType = .symlink
						case _VREG:
							if (returned.commonattr & UInt32(ATTR_CMN_FNDRINFO)) != 0 {
								// FileInfo layout: finderFlags at bytes 8–9, big-endian.
								let b0 = fndrInfoBase.advanced(by: 8).load(as: UInt8.self)
								let b1 = fndrInfoBase.advanced(by: 9).load(as: UInt8.self)
								let finderFlags = UInt16(b0) << 8 | UInt16(b1)
								nodeType = (finderFlags & kIsAlias) != 0 ? .finderAlias : .file
							} else {
								// FNDRINFO was not provided (e.g. SMB share, FAT32). Return nil
								// so the caller can use a Foundation fallback to detect aliases.
								nodeType = nil
							}
						default:
							nodeType = .special
					}

					results.append((name: name, nodeType: nodeType))
					cursor = entryBase.advanced(by: Int(entryLength))
				}
			}

			return results
		}
	}
#endif
