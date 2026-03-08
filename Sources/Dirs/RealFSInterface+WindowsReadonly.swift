#if os(Windows)
	import Foundation
	import SystemPackage
	import WinSDK

	extension RealFSInterface {
		// Probes write access using CreateFileW, since FileManager.isWritableFile ignores ACL deny entries.
		static func isWritablePath(_ path: String) -> Bool {
			let handle = path.withCString(encodedAs: UTF16.self) {
				CreateFileW($0,
							DWORD(FILE_ADD_FILE),
							DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
							nil,
							DWORD(OPEN_EXISTING),
							DWORD(FILE_FLAG_BACKUP_SEMANTICS),
							nil)
			}
			if handle == INVALID_HANDLE_VALUE {
				return false
			}
			CloseHandle(handle)
			return true
		}

		// Makes a directory non-writable or writable on Windows using ACL deny entries.
		// FILE_ATTRIBUTE_READONLY is silently ignored for directories on Windows.
		// Returns a closure that restores the original DACL.
		static func windowsSetWritable(pathString: String,
									   writable: Bool,
									   originalPath: FilePath) throws -> () -> Void
		{
			let attrs = pathString.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
			guard attrs != INVALID_FILE_ATTRIBUTES else {
				throw NoSuchNode(path: originalPath)
			}

			Self.disableBypassPrivilegesOnce()

			var pSD: PSECURITY_DESCRIPTOR? = nil
			var oldDACL: PACL? = nil
			let getResult = pathString.withCString(encodedAs: UTF16.self) {
				GetNamedSecurityInfoW(UnsafeMutablePointer(mutating: $0),
									  SE_FILE_OBJECT,
									  DWORD(DACL_SECURITY_INFORMATION),
									  nil,
									  nil,
									  &oldDACL,
									  nil,
									  &pSD)
			}
			guard getResult == ERROR_SUCCESS else {
				throw NoSuchNode(path: originalPath)
			}

			if writable {
				LocalFree(pSD)
				return {}
			}

			var worldSidAuthority = SID_IDENTIFIER_AUTHORITY(Value: (0, 0, 0, 0, 0, 1))
			var everyoneSID: PSID? = nil
			AllocateAndInitializeSid(&worldSidAuthority,
									 1,
									 DWORD(SECURITY_WORLD_RID),
									 0, 0, 0, 0, 0, 0, 0,
									 &everyoneSID)
			defer { _ = FreeSid(everyoneSID) }

			let denyRights = DWORD(FILE_WRITE_DATA) | DWORD(FILE_ADD_FILE)
				| DWORD(FILE_ADD_SUBDIRECTORY) | DWORD(FILE_DELETE_CHILD)
				| DWORD(DELETE)

			var ea = EXPLICIT_ACCESS_W()
			ea.grfAccessPermissions = denyRights
			ea.grfAccessMode = DENY_ACCESS
			ea.grfInheritance = DWORD(NO_INHERITANCE) | DWORD(OBJECT_INHERIT_ACE) | DWORD(CONTAINER_INHERIT_ACE)
			ea.Trustee.TrusteeForm = TRUSTEE_IS_SID
			ea.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP
			ea.Trustee.ptstrName = everyoneSID?.assumingMemoryBound(to: WCHAR.self)

			var newDACL: PACL? = nil
			SetEntriesInAclW(1, &ea, oldDACL, &newDACL)
			defer { _ = LocalFree(newDACL.map { UnsafeMutableRawPointer($0) }) }

			let setResult = pathString.withCString(encodedAs: UTF16.self) {
				SetNamedSecurityInfoW(UnsafeMutablePointer(mutating: $0),
									  SE_FILE_OBJECT,
									  DWORD(DACL_SECURITY_INFORMATION),
									  nil,
									  nil,
									  newDACL,
									  nil)
			}
			guard setResult == ERROR_SUCCESS else {
				LocalFree(pSD)
				throw PermissionDenied(path: originalPath)
			}

			let capturedSD = pSD
			return {
				pathString.withCString(encodedAs: UTF16.self) {
					_ = SetNamedSecurityInfoW(UnsafeMutablePointer(mutating: $0),
											  SE_FILE_OBJECT,
											  DWORD(DACL_SECURITY_INFORMATION),
											  nil,
											  nil,
											  oldDACL,
											  nil)
				}
				LocalFree(capturedSD)
			}
		}

		private static let _disableBypassPrivileges: Void = {
			var token: HANDLE? = nil
			guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY), &token) else {
				return
			}
			defer { CloseHandle(token) }

			for privilegeName in ["SeBackupPrivilege", "SeRestorePrivilege"] {
				var luid = LUID()
				guard privilegeName.withCString(encodedAs: UTF16.self, { LookupPrivilegeValueW(nil, $0, &luid) }) else {
					continue
				}
				var tp = TOKEN_PRIVILEGES()
				tp.PrivilegeCount = 1
				tp.Privileges.Luid = luid
				tp.Privileges.Attributes = 0
				AdjustTokenPrivileges(token, false, &tp, 0, nil, nil)
			}
		}()

		private static func disableBypassPrivilegesOnce() {
			_ = Self._disableBypassPrivileges
		}
	}
#endif
