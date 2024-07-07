import Foundation
import SystemPackage

public extension Dir {
	/// The system's temporary folder.
	static func temporary(in filesystemInterface: any FilesystemInterface) throws -> Dir {
		try filesystemInterface.createDir(at: FilePath(NSTemporaryDirectory()))
	}
}

public extension Dir {
	func createFile(at ifp: some IntoFilePath, contents: some IntoData) throws -> File {
		let file = try self.createFile(at: ifp.into())
		try file.setContents(contents)
		return file
	}
}
