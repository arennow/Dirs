import Foundation
import SystemPackage

public extension Dir {
	/// The system's temporary folder.
	static func temporary(in filesystemInterface: any FilesystemInterface) throws -> Dir {
		try filesystemInterface.createDir(at: FilePath(NSTemporaryDirectory()))
	}
}
